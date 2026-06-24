#if os(iOS)
import Foundation
import ActivityKit

/// Shared contract between the app (which starts/updates/ends the activity) and the widget
/// extension (which renders it on the Lock Screen + Dynamic Island). iOS-only — ActivityKit
/// doesn't exist on macOS, so the whole file is compiled out there.
struct PrayerActivityAttributes: ActivityAttributes {
    /// The live, changing part — refreshed as the phase / prayer flips.
    public struct ContentState: Codable, Hashable {
        var prayerName: String
        var prayerArabicName: String
        var isIqama: Bool          // true → counting down to iqama; false → to azan
        var targetTime: Date       // the instant the countdown lands on (azan or iqama)
        var azanTime: Date
        var iqamaLeadMinutes: Int
    }

    /// Fixed for the life of the activity.
    var areaName: String
}
#endif
