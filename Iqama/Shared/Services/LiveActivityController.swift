#if os(iOS)
import Foundation
import ActivityKit

/// Drives the Lock Screen / Dynamic Island Live Activity from the same `CountdownSnapshot`
/// the rest of the app uses. The countdown itself ticks via SwiftUI's `Text(_:style:.timer)`
/// inside the activity, so we only push a new content state when the *phase* flips
/// (next prayer, or azan → iqama) — not every second.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var activity: Activity<PrayerActivityAttributes>?
    private var lastSignature: String?
    private var didReconnect = false

    /// Start (or update) the activity to match the current snapshot. No-op if the user has
    /// Live Activities disabled system-wide.
    func sync(with snapshot: CountdownSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Live Activities outlive the app process. On the first sync after a (re)launch, adopt
        // whatever is already on screen and end any leftovers — otherwise we stack a second
        // activity on top of the previous session's one (the stale "counting up" duplicate).
        reconnectToExistingIfNeeded()

        let prayer = snapshot.phase.prayer
        let isIqama = snapshot.phase.isIqamaPhase
        let target = snapshot.phase.targetTime
        let day = snapshot.todayPrayerTimes
        let azan = day?.prayerTime(for: prayer) ?? target
        let lead = snapshot.azanSettings?.iqamaMinutes(for: prayer, isFriday: day?.isFriday ?? false) ?? 0
        let areaName = day?.areaNameEn ?? ""

        // Only act when the meaningful state changes (avoids a push per second).
        let signature = "\(prayer.rawValue)|\(isIqama)|\(Int(target.timeIntervalSince1970))"
        guard signature != lastSignature else { return }
        lastSignature = signature

        let state = PrayerActivityAttributes.ContentState(
            prayerName: prayer.displayName,
            prayerArabicName: prayer.arabicName,
            isIqama: isIqama,
            targetTime: target,
            azanTime: azan,
            iqamaLeadMinutes: lead
        )
        let content = ActivityContent(state: state, staleDate: target.addingTimeInterval(60))

        if let activity {
            Task { await activity.update(content) }
        } else {
            let attributes = PrayerActivityAttributes(areaName: areaName)
            do {
                activity = try Activity.request(attributes: attributes, content: content)
            } catch {
                // Throttled / disabled — try again on the next phase change.
                lastSignature = nil
            }
        }
    }

    /// Adopt an already-running activity once per launch and collapse any duplicates to one.
    private func reconnectToExistingIfNeeded() {
        guard !didReconnect else { return }
        didReconnect = true
        let running = Activity<PrayerActivityAttributes>.activities
        guard let keep = running.first else { return }
        activity = keep
        lastSignature = nil                 // force the next update to refresh its phase
        for extra in running.dropFirst() {  // end leftovers from earlier launches
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Tear all activities down (e.g. when prayer data goes unavailable).
    func end() {
        activity = nil
        lastSignature = nil
        for a in Activity<PrayerActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif
