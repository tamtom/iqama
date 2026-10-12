#if os(iOS)
import Foundation
import ActivityKit

/// Shared contract between the app (which schedules and ends the activity) and the widget
/// extension (which renders it on the Lock Screen + Dynamic Island). iOS-only — ActivityKit
/// doesn't exist on macOS, so the whole file is compiled out there.
///
/// One activity covers one prayer's azan → iqama window. It never changes after it starts, so
/// everything lives in the static attributes; the content state only carries the times the
/// countdown needs.
struct PrayerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var azanTime: Date
        var iqamaTime: Date
    }

    var prayerName: String
    var prayerArabicName: String
    /// "Asr|<azan epoch>|<iqama epoch>" — identifies the window, so an offset change yields a new id.
    var windowID: String
}
#endif
