import SwiftUI

/// Sky colors for one moment, anchored to the real sunrise and sunset of the day, so a winter
/// morning and a summer morning both start blue at the actual sunrise.
struct SkyColors {
    var zenith: Color       // top of the sky
    var horizon: Color      // bottom of the sky
    var glow: Color         // light around the sun or moon
    var light: Double       // 0 = night … 1 = full daylight

    /// The far city: the horizon color seen through haze, darker when there's less light.
    var cityColor: Color {
        Theme.blend(Theme.blend(horizon, zenith, 0.45), .black, 0.22 + 0.4 * (1 - light))
    }

    /// The near mosque and the ground under it: a deep version of the sky, never pure black
    /// by day.
    var groundColor: Color {
        Theme.blend(zenith, .black, 0.55 + 0.3 * (1 - light))
    }
}

enum SkyPalette {
    private struct Key {
        let minutes: Double   // offset from the anchor
        let anchor: Anchor
        let zenith: (Double, Double, Double)
        let horizon: (Double, Double, Double)
        let glow: (Double, Double, Double)
        let light: Double
    }

    private enum Anchor { case sunrise, noon, sunset }

    private static let night = Key(minutes: 0, anchor: .sunrise,
                                   zenith: (0.03, 0.05, 0.13), horizon: (0.07, 0.09, 0.22),
                                   glow: (0.80, 0.86, 1.00), light: 0)

    // In time order through one day.
    private static let keys: [Key] = [
        Key(minutes: -100, anchor: .sunrise, zenith: night.zenith, horizon: night.horizon, glow: night.glow, light: 0),
        Key(minutes: -50, anchor: .sunrise, zenith: (0.06, 0.08, 0.20), horizon: (0.24, 0.18, 0.36), glow: (0.95, 0.70, 0.75), light: 0.1),
        Key(minutes: -15, anchor: .sunrise, zenith: (0.16, 0.22, 0.45), horizon: (0.92, 0.56, 0.44), glow: (1.00, 0.72, 0.52), light: 0.35),
        Key(minutes: 25, anchor: .sunrise, zenith: (0.30, 0.50, 0.80), horizon: (1.00, 0.79, 0.60), glow: (1.00, 0.88, 0.70), light: 0.7),
        Key(minutes: 90, anchor: .sunrise, zenith: (0.22, 0.50, 0.88), horizon: (0.62, 0.81, 0.97), glow: (1.00, 0.98, 0.92), light: 1),
        Key(minutes: 0, anchor: .noon, zenith: (0.13, 0.42, 0.86), horizon: (0.54, 0.77, 0.98), glow: (1.00, 1.00, 0.97), light: 1),
        Key(minutes: -90, anchor: .sunset, zenith: (0.18, 0.45, 0.84), horizon: (0.68, 0.80, 0.94), glow: (1.00, 0.96, 0.86), light: 0.95),
        Key(minutes: -30, anchor: .sunset, zenith: (0.26, 0.40, 0.72), horizon: (0.99, 0.72, 0.46), glow: (1.00, 0.80, 0.52), light: 0.8),
        Key(minutes: 5, anchor: .sunset, zenith: (0.18, 0.18, 0.42), horizon: (0.98, 0.45, 0.22), glow: (1.00, 0.55, 0.30), light: 0.45),
        Key(minutes: 35, anchor: .sunset, zenith: (0.08, 0.08, 0.24), horizon: (0.50, 0.22, 0.34), glow: (0.95, 0.55, 0.55), light: 0.15),
        Key(minutes: 90, anchor: .sunset, zenith: night.zenith, horizon: night.horizon, glow: night.glow, light: 0),
    ]

    /// Without data, sunrise 06:00 and sunset 18:15.
    static func colors(at date: Date, sunrise: Date?, sunset: Date?) -> SkyColors {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let rise = sunrise.map { sameDay($0, as: date) } ?? start.addingTimeInterval(6 * 3600)
        let set = sunset.map { sameDay($0, as: date) } ?? start.addingTimeInterval(18.25 * 3600)
        let noon = rise.addingTimeInterval(set.timeIntervalSince(rise) / 2)

        func time(_ key: Key) -> Date {
            let base: Date
            switch key.anchor {
            case .sunrise: base = rise
            case .noon: base = noon
            case .sunset: base = set
            }
            return base.addingTimeInterval(key.minutes * 60)
        }

        guard let first = keys.first, let last = keys.last,
              date > time(first), date < time(last) else { return make(night, night, 0) }
        for (a, b) in zip(keys, keys.dropFirst()) {
            let ta = time(a), tb = time(b)
            if date >= ta && date <= tb {
                let f = tb > ta ? date.timeIntervalSince(ta) / tb.timeIntervalSince(ta) : 0
                return make(a, b, smooth(f))
            }
        }
        return make(night, night, 0)
    }

    /// Moves a sunrise / sunset time onto the calendar day of `date` (keeps its clock time).
    private static func sameDay(_ time: Date, as date: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                             second: parts.second ?? 0, of: date) ?? time
    }

    private static func smooth(_ f: Double) -> Double { f * f * (3 - 2 * f) }

    private static func make(_ a: Key, _ b: Key, _ f: Double) -> SkyColors {
        func c(_ x: (Double, Double, Double), _ y: (Double, Double, Double)) -> Color {
            Color(.sRGB, red: x.0 + (y.0 - x.0) * f, green: x.1 + (y.1 - x.1) * f,
                  blue: x.2 + (y.2 - x.2) * f, opacity: 1)
        }
        return SkyColors(zenith: c(a.zenith, b.zenith), horizon: c(a.horizon, b.horizon),
                         glow: c(a.glow, b.glow), light: a.light + (b.light - a.light) * f)
    }
}
