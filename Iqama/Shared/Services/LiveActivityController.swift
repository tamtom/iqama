#if os(iOS)
import Foundation
import ActivityKit

/// Shows one Live Activity per prayer, from its azan to its iqama.
///
/// iOS can schedule an activity to start later (`request(...start:)`, iOS 26), so upcoming
/// windows start at their azan even while the app is suspended. iOS has no way to end an
/// activity at a set time, though: at iqama the activity goes stale (the view shows "Iqama now")
/// and the app ends it the next time it runs — in the foreground, or in the background refresh
/// task that `BackgroundRefresh` schedules for the iqama time.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    /// Windows to keep started or scheduled at once. Scheduled activities count toward the
    /// system's per-app limit, so keep this small; each reconcile tops the queue back up.
    private static let maxWindows = 3
    private static let requestedKey = "liveActivityRequestedWindows"

    private var lastPhaseSignature: String?
    private var lastReconcile = Date.distantPast

    struct Window {
        let prayer: Prayer
        let azan: Date
        let iqama: Date

        var id: String {
            "\(prayer.rawValue)|\(Int(azan.timeIntervalSince1970))|\(Int(iqama.timeIntervalSince1970))"
        }
    }

    /// Called every second by `CountdownManager`. Reconciles when the phase flips (so the
    /// activity ends right at iqama while the app is open) and once a minute to pick up
    /// settings changes.
    func sync(with snapshot: CountdownSnapshot) {
        let now = Date()
        let signature = "\(snapshot.phase.prayer.rawValue)|\(snapshot.phase.isIqamaPhase)|\(Int(snapshot.phase.targetTime.timeIntervalSince1970))"
        guard signature != lastPhaseSignature || now.timeIntervalSince(lastReconcile) >= 60 else { return }
        lastPhaseSignature = signature
        reconcile(now: now)
    }

    /// Make the running and scheduled activities match the upcoming prayer windows: end
    /// activities whose iqama passed (or whose times changed), then start or schedule the rest.
    func reconcile(now: Date = Date()) {
        lastReconcile = now
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let windows = Self.upcomingWindows(after: now)
        let wanted = Set(windows.map(\.id))

        var present = Set<String>()
        for activity in Activity<PrayerActivityAttributes>.activities {
            let id = activity.attributes.windowID
            let isLive = activity.activityState == .active || activity.activityState == .stale
                || activity.activityState == .pending
            if wanted.contains(id), isLive, !present.contains(id) {
                present.insert(id)
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }

        // Request a live window once. If the user swipes an activity away, it stays away until
        // the next prayer instead of coming back on the next reconcile. A window that has not
        // started yet is requested again when it is missing: the user cannot swipe it away, but
        // iOS removes scheduled activities when a new build of the app installs.
        var requested = Self.requestedWindows(pruningBefore: now)
        for window in windows where !present.contains(window.id)
            && (window.azan > now || !requested.contains(window.id)) {
            guard request(window, now: now) else { break }  // limit reached or not allowed now
            requested.insert(window.id)
        }
        UserDefaults.standard.set(Array(requested), forKey: Self.requestedKey)
    }

    /// Tear all activities down (e.g. when prayer data goes unavailable).
    func end() {
        lastPhaseSignature = nil
        for activity in Activity<PrayerActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The earliest iqama of a started or scheduled activity — when the background task should
    /// run to end it.
    var nextEndDate: Date? {
        Activity<PrayerActivityAttributes>.activities
            .map(\.content.state.iqamaTime)
            .filter { $0 > Date() }
            .min()
    }

    // MARK: - Private

    private func request(_ window: Window, now: Date) -> Bool {
        let attributes = PrayerActivityAttributes(
            prayerName: window.prayer.displayName,
            prayerArabicName: window.prayer.arabicName,
            windowID: window.id
        )
        // Later windows get a higher score, so the newest one wins the Dynamic Island over a
        // stale one the app couldn't end yet.
        let content = ActivityContent(
            state: PrayerActivityAttributes.ContentState(azanTime: window.azan, iqamaTime: window.iqama),
            staleDate: window.iqama,
            relevanceScore: window.azan.timeIntervalSince1970 / 60
        )
        do {
            if window.azan <= now {
                _ = try Activity.request(attributes: attributes, content: content)
            } else {
                let minutes = Int(window.iqama.timeIntervalSince(window.azan) / 60)
                let alert = AlertConfiguration(
                    title: "\(window.prayer.displayName) Azan",
                    body: "Iqama in \(minutes) min",
                    sound: .default
                )
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil,
                                         style: .standard, alertConfiguration: alert,
                                         start: window.azan)
            }
            return true
        } catch {
            return false
        }
    }

    /// The next prayer windows whose iqama is still ahead, across today and tomorrow.
    static func upcomingWindows(after now: Date) -> [Window] {
        let calendar = Calendar.current
        var result: [Window] = []
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let times = try? PrayerTimesService.shared.getAllPrayerTimes(for: day) else { continue }
            for t in times where t.iqamaTime > now && t.iqamaTime > t.azanTime {
                result.append(Window(prayer: t.prayer, azan: t.azanTime, iqama: t.iqamaTime))
            }
        }
        return Array(result.prefix(maxWindows))
    }

    /// Window ids already requested, minus the ones whose iqama is over a day old.
    private static func requestedWindows(pruningBefore now: Date) -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: requestedKey) ?? []
        let cutoff = now.timeIntervalSince1970 - 86_400
        return Set(ids.filter { id in
            guard let iqama = id.split(separator: "|").last.flatMap({ TimeInterval($0) }) else { return false }
            return iqama > cutoff
        })
    }
}
#endif
