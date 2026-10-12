import Foundation
import Combine
import UserNotifications

/// Sends the pre-iqama reminder and, for nag-enabled prayers, runs the "did you pray?"
/// follow-up loop: the pre-iqama reminder gains commitment actions, the first confirmation
/// fires at iqama + interval, and it re-asks every interval until the user confirms
/// ("Yes, Wallah") or the prayer's window ends (the next prayer's azan).
///
/// The same state drives the in-app check-in card: `pendingCheckIn` is published whenever
/// there's an unanswered commitment/confirmation, so the UI can offer the answers inline
/// (macOS banners vanish after a few seconds unless the user sets the style to Alerts).
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// What the in-app card should show right now (nil = nothing pending / snoozed).
    struct CheckInState: Equatable {
        let prayer: Prayer
        let awaitingConfirmation: Bool  // false → pre-iqama commitment stage
    }

    @Published private(set) var pendingCheckIn: CheckInState?

    // MARK: - Categories / actions

    private enum CategoryID {
        static let preIqama = "PRE_IQAMA"       // pre-iqama reminder with commitment actions
        static let didYouPray = "DID_YOU_PRAY"  // post-iqama confirmation
    }

    private enum ActionID {
        static let goingToPray = "GOING_TO_PRAY"  // "Wallah, going to pray now" — stops the loop
        static let remindLater = "REMIND_LATER"   // pre-iqama "Remind me later" — loop proceeds
        static let prayedYes = "PRAYED_YES"       // "Yes, Wallah" — stops the loop
        static let remindAgain = "REMIND_AGAIN"   // confirmation "Remind me later" — re-ask in one interval
    }

    // MARK: - State

    // Pre-iqama reminder dedupe (one banner per prayer at the configured lead).
    private var hasNotifiedForCurrentIqama = false
    private var lastNotifiedPrayer: Prayer?
    private var lastNotifiedLead: Int?

    /// One nag window is live at a time: it opens at the prayer's azan (so the pre-iqama
    /// banner can carry its key) and closes at the NEXT prayer's azan.
    private struct NagWindow {
        let prayer: Prayer
        let key: String                  // "Zuhr|2026-06-11" — unique per prayer + day
        let iqamaTime: Date
        var resolved: Bool               // user committed to pray / confirmed praying
        var nextAskAt: Date              // when the next "did you pray?" fires
        var snoozedUntil: Date?          // hides the in-app card after "remind me later"
        var askCount = 0
        var deliveredIDs: [String] = []  // confirmation banners we can clear once resolved
    }

    private var window: NagWindow?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let going = UNNotificationAction(identifier: ActionID.goingToPray, title: "Wallah, going to pray now")
        let later = UNNotificationAction(identifier: ActionID.remindLater, title: "Remind me later")
        let preIqama = UNNotificationCategory(identifier: CategoryID.preIqama,
                                              actions: [going, later], intentIdentifiers: [])

        let prayed = UNNotificationAction(identifier: ActionID.prayedYes, title: "Yes, Wallah")
        let again = UNNotificationAction(identifier: ActionID.remindAgain, title: "Remind me later")
        let didYouPray = UNNotificationCategory(identifier: CategoryID.didYouPray,
                                                actions: [prayed, again], intentIdentifiers: [])

        UNUserNotificationCenter.current().setNotificationCategories([preIqama, didYouPray])
    }

    // MARK: - Permission

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            #if os(iOS)
            // Requests added before the user answered were dropped; schedule them again.
            if granted {
                DispatchQueue.main.async { self.scheduleUpcoming(force: true) }
            }
            #endif
            if let completion {
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - In-app card actions

    /// "Wallah, going to pray now" / "Yes, Wallah" tapped inside the app.
    func confirmPrayed() {
        resolveWindow()
    }

    /// "Later" tapped inside the app: hide the card until the next ask is due.
    func snoozeCheckIn() {
        guard var w = window, !w.resolved else { return }
        if Date() >= w.iqamaTime {
            w.nextAskAt = Date().addingTimeInterval(nagInterval)
        }
        // Pre-iqama: the first post-iqama ask (iqama + interval) is the "later".
        w.snoozedUntil = w.nextAskAt
        window = w
        publishState()
    }

    // MARK: - Per-second tick (from CountdownManager, main thread)

    func tick(snapshot: CountdownSnapshot) {
        #if os(iOS)
        scheduleUpcomingIfDue()
        #endif
        guard AppSettings.notificationsEnabled else {
            hasNotifiedForCurrentIqama = false
            lastNotifiedPrayer = nil
            closeWindow()
            return
        }
        syncWindow(to: snapshot)
        checkPreIqama(snapshot: snapshot)
        checkNagLoop()
        publishState()
    }

    /// Keeps `window` aligned with the countdown phase: open it at azan, keep it through the
    /// post-iqama stretch, drop it when the next prayer's azan arrives (or nagging is off).
    private func syncWindow(to snapshot: CountdownSnapshot) {
        let now = Date()
        switch snapshot.phase {
        case .waitingForIqama(let prayer, let iqamaTime):
            // Azan has passed — this prayer's window opens; any previous window just ended.
            guard AppSettings.nagEnabled(for: prayer) else { closeWindow(); return }
            let key = Self.windowKey(for: prayer, on: now)
            guard window?.key != key else { return }
            closeWindow()
            window = NagWindow(prayer: prayer, key: key, iqamaTime: iqamaTime,
                               resolved: AppSettings.nagResolvedWindow == key,
                               nextAskAt: iqamaTime.addingTimeInterval(nagInterval))

        case .waitingForAzan(let upcoming, let azanTime):
            // Between a prayer's iqama and the next azan — `upcoming.previous`'s window is live.
            let prayer = upcoming.previous
            guard AppSettings.nagEnabled(for: prayer) else { closeWindow(); return }
            // Anchor the key to the prayer's own day (isha's window crosses midnight).
            let anchor = upcoming == .fajr ? azanTime.addingTimeInterval(-86400) : now
            let key = Self.windowKey(for: prayer, on: anchor)
            guard window?.key != key else { return }
            // App launched mid-window: rebuild state; first ask comes one interval from now.
            closeWindow()
            window = NagWindow(prayer: prayer, key: key, iqamaTime: now,
                               resolved: AppSettings.nagResolvedWindow == key,
                               nextAskAt: now.addingTimeInterval(nagInterval))
        }
    }

    private func checkNagLoop() {
        guard var w = window, !w.resolved, Date() >= w.nextAskAt else { return }
        w.askCount += 1
        let id = "nag-confirm-\(w.key)-\(w.askCount)"
        w.deliveredIDs.append(id)
        w.nextAskAt = Date().addingTimeInterval(nagInterval)
        w.snoozedUntil = nil  // the ask is due again — surface the in-app card too
        window = w

        let minutes = AppSettings.nagIntervalMinutes
        let content = UNMutableNotificationContent()
        content.title = "Did you pray \(w.prayer.displayName)?"
        content.body = "\(w.prayer.arabicName) — confirm to stop the reminders, or I'll check again in \(minutes) min."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = CategoryID.didYouPray
        content.userInfo = ["windowKey": w.key]
        deliver(content, identifier: id)
    }

    private var nagInterval: TimeInterval {
        TimeInterval(AppSettings.nagIntervalMinutes * 60)
    }

    /// Marks the live window answered, persists it, and clears lingering banners.
    private func resolveWindow() {
        guard var w = window, !w.resolved else { return }
        w.resolved = true
        AppSettings.nagResolvedWindow = w.key  // survives relaunch — don't re-nag
        #if os(iOS)
        cancelScheduled(forKey: w.key)
        #endif
        if !w.deliveredIDs.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: w.deliveredIDs)
            w.deliveredIDs = []
        }
        window = w
        publishState()
    }

    /// Clears any lingering confirmation banners and drops the window.
    private func closeWindow() {
        if let ids = window?.deliveredIDs, !ids.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
        window = nil
        publishState()
    }

    /// Mirrors the window into the published card state (only on change — this runs every second).
    private func publishState() {
        var state: CheckInState?
        if let w = window, !w.resolved {
            let now = Date()
            let snoozed = w.snoozedUntil.map { now < $0 } ?? false
            if !snoozed {
                state = CheckInState(prayer: w.prayer, awaitingConfirmation: now >= w.iqamaTime)
            }
        }
        if state != pendingCheckIn { pendingCheckIn = state }
    }

    // MARK: - Pre-iqama reminder

    private func checkPreIqama(snapshot: CountdownSnapshot) {
        guard AppSettings.notificationLeadMinutes > 0 else {
            hasNotifiedForCurrentIqama = false
            lastNotifiedPrayer = nil
            return
        }
        let setting = AppSettings.notificationLeadMinutes

        guard case .waitingForIqama(let prayer, _) = snapshot.phase else {
            // Reset when not in iqama phase
            hasNotifiedForCurrentIqama = false
            lastNotifiedPrayer = nil
            return
        }

        // A lead longer than the azan → iqama gap (Maghrib's 5 min) reminds at the azan instead.
        let gap = snapshot.azanSettings?.iqamaMinutes(for: prayer, isFriday: snapshot.todayPrayerTimes?.isFriday ?? false) ?? setting
        let lead = min(setting, gap)
        guard lead > 0 else { return }

        // Already fired for this prayer at the current lead setting.
        if hasNotifiedForCurrentIqama && lastNotifiedPrayer == prayer && lastNotifiedLead == lead {
            return
        }

        // Fire when remaining time enters the [lead-1m, lead] window. Using a 1-min
        // band avoids re-firing as the countdown ticks across the threshold.
        let upper: TimeInterval = TimeInterval(lead) * 60
        let lower: TimeInterval = TimeInterval(max(0, lead - 1)) * 60

        if snapshot.timeRemaining <= upper && snapshot.timeRemaining > lower {
            sendIqamaNotification(for: prayer, minutesRemaining: lead)
            hasNotifiedForCurrentIqama = true
            lastNotifiedPrayer = prayer
            lastNotifiedLead = lead
        }
    }

    private func sendIqamaNotification(for prayer: Prayer, minutesRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(prayer.displayName) Iqama"
        content.body = "\(minutesRemaining) minute\(minutesRemaining == 1 ? "" : "s") until \(prayer.displayName) Iqama"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        // Nag-enabled prayers get the commitment actions on the same banner.
        if let w = window, w.prayer == prayer {
            content.categoryIdentifier = CategoryID.preIqama
            content.userInfo = ["windowKey": w.key]
        }
        deliver(content, identifier: "iqama-\(prayer.rawValue)-\(Date().timeIntervalSince1970)")
    }

    // MARK: - Azan alert

    /// The alert at a prayer's azan time. On iOS its sound is the short Adhan clip, because iOS
    /// plays at most 30 seconds of a notification sound. The clip plays only when the app is
    /// closed or in the background. While the app is open, the alert shows without its sound.
    private static func azanContent(for prayer: Prayer, iqamaMinutes: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(prayer.displayName) Azan"
        content.body = iqamaMinutes > 0
            ? "\(prayer.arabicName) — iqama in \(iqamaMinutes) minute\(iqamaMinutes == 1 ? "" : "s")."
            : prayer.arabicName
        content.interruptionLevel = .timeSensitive
        #if os(iOS)
        content.sound = UNNotificationSound(named: AppSettings.adhanSound.alertSoundName)
        #endif
        return content
    }

    #if os(macOS)
    /// macOS: the menu bar app runs all the time, so `AdhanPlayer` plays the full Adhan. This
    /// banner has no sound.
    func postAzanBanner(for prayer: Prayer, iqamaMinutes: Int) {
        let content = Self.azanContent(for: prayer, iqamaMinutes: iqamaMinutes)
        deliver(content, identifier: "azan-\(prayer.rawValue)-\(Date().timeIntervalSince1970)")
    }
    #endif

    private func deliver(_ content: UNNotificationContent, identifier: String) {
        // iOS suspends the app, so the per-second tick can't deliver on time. There the scheduled
        // requests from `scheduleUpcoming()` deliver instead, and the tick only drives the in-app card.
        #if os(macOS)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
        #endif
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The Adhan plays only when the app is closed or in the background, so the open app
        // shows the azan alert without its sound.
        if notification.request.identifier.hasPrefix("azan-") {
            completionHandler([.banner, .list])
            return
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let key = response.notification.request.content.userInfo["windowKey"] as? String
        DispatchQueue.main.async { [weak self] in
            self?.handleResponse(action: action, windowKey: key)
            completionHandler()
        }
    }

    private func handleResponse(action: String, windowKey: String?) {
        #if os(iOS)
        // The action can relaunch the app before the first tick rebuilds `window`. The answer
        // must still stop that window's scheduled asks.
        if let windowKey, action == ActionID.goingToPray || action == ActionID.prayedYes,
           window?.key != windowKey {
            AppSettings.nagResolvedWindow = windowKey
            cancelScheduled(forKey: windowKey)
            return
        }
        #endif
        // Responses from stale windows (yesterday's banner, a prayer whose window ended) are moot.
        guard let windowKey, let w = window, w.key == windowKey else { return }
        switch action {
        case ActionID.goingToPray, ActionID.prayedYes:
            resolveWindow()
        case ActionID.remindLater, ActionID.remindAgain:
            snoozeCheckIn()  // pre-iqama: first ask stays at iqama + interval; after: pushes it out
        default:
            break  // clicked the banner body or dismissed — counts as no response
        }
    }

    #if os(iOS)
    // MARK: - Scheduled delivery (iOS)

    private static let scheduledPrefixes = ["azan-", "iqama-", "nag-confirm-"]
    /// iOS keeps at most 64 pending requests per app; leave room for the system.
    private static let maxScheduled = 60
    private static let maxAsksPerPrayer = 8

    private var lastPlanSignature: String?
    private var lastPlanCheck = Date.distantPast

    private struct PlannedNotification {
        let id: String
        let date: Date
        let content: UNMutableNotificationContent
    }

    private func scheduleUpcomingIfDue() {
        guard Date().timeIntervalSince(lastPlanCheck) >= 10 else { return }
        scheduleUpcoming()
    }

    /// Replace the pending pre-iqama reminders and "did you pray?" asks with the plan for the
    /// next prayers. Cheap to call often: it only touches the pending requests when the plan
    /// changes, unless `force` is set (the permission or the system settings can change too).
    func scheduleUpcoming(force: Bool = false) {
        let now = Date()
        lastPlanCheck = now
        let plan = plannedNotifications(now: now)
        // The sound is in the signature, so a new Adhan choice replaces the pending azan alerts.
        let signature = AppSettings.adhanSound.rawValue + ";"
            + plan.map { "\($0.id)@\(Int($0.date.timeIntervalSince1970))" }.joined(separator: ",")
        guard force || signature != lastPlanSignature else { return }
        lastPlanSignature = signature

        let center = UNUserNotificationCenter.current()
        let wanted = Set(plan.map(\.id))
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { id in
                Self.scheduledPrefixes.contains(where: id.hasPrefix) && !wanted.contains(id)
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let calendar = Calendar.current
            for item in plan {
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: item.content, trigger: trigger))
            }
        }
    }

    private func plannedNotifications(now: Date) -> [PlannedNotification] {
        let calendar = Calendar.current

        // Yesterday too: its isha window can still be open after midnight.
        var windows: [(prayer: Prayer, azan: Date, iqama: Date, day: Date)] = []
        for offset in -1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let times = try? PrayerTimesService.shared.getAllPrayerTimes(for: day) else { continue }
            windows += times.map { (prayer: $0.prayer, azan: $0.azanTime, iqama: $0.iqamaTime, day: day) }
        }
        windows.sort { $0.azan < $1.azan }

        let lead = AppSettings.notificationLeadMinutes
        var plan: [PlannedNotification] = []
        for (index, w) in windows.enumerated() {
            let key = Self.windowKey(for: w.prayer, on: w.day)

            // The azan alert has its own switch for each prayer, apart from the iqama reminders.
            if AppSettings.adhanEnabled(for: w.prayer), w.azan > now {
                let gap = Int(w.iqama.timeIntervalSince(w.azan) / 60)
                plan.append(PlannedNotification(id: "azan-\(key)", date: w.azan,
                                                content: Self.azanContent(for: w.prayer, iqamaMinutes: gap)))
            }
            guard AppSettings.notificationsEnabled else { continue }

            let nagging = AppSettings.nagEnabled(for: w.prayer) && AppSettings.nagResolvedWindow != key

            // Same rule as the tick: a lead longer than the azan → iqama gap reminds at the azan.
            let minutes = min(lead, Int(w.iqama.timeIntervalSince(w.azan) / 60))
            let reminderAt = w.iqama.addingTimeInterval(-TimeInterval(minutes * 60))
            if minutes > 0, reminderAt > now {
                let content = UNMutableNotificationContent()
                content.title = "\(w.prayer.displayName) Iqama"
                content.body = "\(minutes) minute\(minutes == 1 ? "" : "s") until \(w.prayer.displayName) Iqama"
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                if nagging {
                    content.categoryIdentifier = CategoryID.preIqama
                    content.userInfo = ["windowKey": key]
                }
                plan.append(PlannedNotification(id: "iqama-\(key)", date: reminderAt, content: content))
            }

            // Asks at iqama + n × interval until the next prayer's azan closes the window.
            guard nagging, nagInterval > 0, index + 1 < windows.count else { continue }
            let windowEnd = windows[index + 1].azan
            for ask in 1...Self.maxAsksPerPrayer {
                let askAt = w.iqama.addingTimeInterval(nagInterval * Double(ask))
                guard askAt < windowEnd else { break }
                guard askAt > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Did you pray \(w.prayer.displayName)?"
                content.body = "\(w.prayer.arabicName) — confirm to stop the reminders, or I'll check again in \(AppSettings.nagIntervalMinutes) min."
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                content.categoryIdentifier = CategoryID.didYouPray
                content.userInfo = ["windowKey": key]
                plan.append(PlannedNotification(id: "nag-confirm-\(key)-\(ask)", date: askAt, content: content))
            }
        }
        return Array(plan.sorted { $0.date < $1.date }.prefix(Self.maxScheduled))
    }

    /// Drop the pending and delivered asks of a window the user answered, then re-plan.
    private func cancelScheduled(forKey key: String) {
        let center = UNUserNotificationCenter.current()
        let matches: (String) -> Bool = { $0 == "iqama-\(key)" || $0.hasPrefix("nag-confirm-\(key)-") }
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(matches))
        }
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter(matches))
        }
        scheduleUpcoming(force: true)
    }
    #endif

    // MARK: - Window keys

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func windowKey(for prayer: Prayer, on day: Date) -> String {
        "\(prayer.rawValue)|\(dayFormatter.string(from: day))"
    }
}
