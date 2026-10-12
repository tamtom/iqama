import Foundation

enum CountdownPhase: Equatable {
    case waitingForAzan(prayer: Prayer, azanTime: Date)
    case waitingForIqama(prayer: Prayer, iqamaTime: Date)

    var prayer: Prayer {
        switch self {
        case .waitingForAzan(let prayer, _),
             .waitingForIqama(let prayer, _):
            return prayer
        }
    }

    var targetTime: Date {
        switch self {
        case .waitingForAzan(_, let time),
             .waitingForIqama(_, let time):
            return time
        }
    }

    var displayLabel: String {
        switch self {
        case .waitingForAzan(let prayer, _):
            return "\(prayer.displayName)"
        case .waitingForIqama(let prayer, _):
            return "\(prayer.displayName) Iqama"
        }
    }

    var isIqamaPhase: Bool {
        if case .waitingForIqama = self {
            return true
        }
        return false
    }
}

struct CountdownSnapshot {
    let phase: CountdownPhase
    let timeRemaining: TimeInterval
    let todayPrayerTimes: DailyPrayerTimes?
    let azanSettings: AzanSettings?
    /// The sunrise, when it comes before the next prayer phase. The countdown then shows the
    /// time to the sunrise. `phase` and `timeRemaining` stay on the prayer, so the alerts and
    /// the Adhan do not change.
    var sunrise: Date? = nil

    /// The time to what the countdown shows: the sunrise, or the next azan or iqama.
    var displayRemaining: TimeInterval {
        guard let sunrise else { return timeRemaining }
        return max(0, timeRemaining - phase.targetTime.timeIntervalSince(sunrise))
    }

    var formattedTimeRemaining: String {
        let totalSeconds = Int(max(0, displayRemaining))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var shortFormattedTime: String {
        let totalSeconds = Int(max(0, displayRemaining))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm", minutes)
        } else {
            return "<1m"
        }
    }

    var statusBarText: String {
        let label = sunrise != nil ? "Sunrise" : phase.displayLabel
        return "\(label) \(shortFormattedTime)"
    }
}
