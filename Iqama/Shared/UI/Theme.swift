import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Time-of-day sky palette. Colors are picked so the gradient is always
// readable (text contrast preserved) across the full 24-hour cycle.
struct SkyKeyframe {
    let hour: Double
    let top: Color
    let bottom: Color
}

enum Theme {
    // Palette is intentionally deep / cinematic at every hour so white text
    // always sits on a dark base. Hue shifts through the day; value stays low.
    static let keyframes: [SkyKeyframe] = [
        .init(hour:  0, top: rgb(0.04, 0.05, 0.12), bottom: rgb(0.07, 0.06, 0.18)),  // deep night
        .init(hour:  4, top: rgb(0.07, 0.06, 0.18), bottom: rgb(0.18, 0.10, 0.26)),  // pre-dawn
        .init(hour:  5, top: rgb(0.12, 0.10, 0.24), bottom: rgb(0.36, 0.18, 0.28)),  // dawn rose
        .init(hour:  7, top: rgb(0.12, 0.18, 0.32), bottom: rgb(0.44, 0.26, 0.24)),  // sunrise
        .init(hour: 10, top: rgb(0.08, 0.18, 0.34), bottom: rgb(0.20, 0.32, 0.46)),  // mid-morning teal
        .init(hour: 12, top: rgb(0.06, 0.16, 0.34), bottom: rgb(0.18, 0.34, 0.50)),  // noon (deep teal-blue)
        .init(hour: 15, top: rgb(0.10, 0.14, 0.32), bottom: rgb(0.32, 0.22, 0.34)),  // afternoon
        .init(hour: 17, top: rgb(0.20, 0.12, 0.32), bottom: rgb(0.52, 0.22, 0.22)),  // pre-sunset
        .init(hour: 18, top: rgb(0.26, 0.10, 0.28), bottom: rgb(0.60, 0.24, 0.16)),  // sunset
        .init(hour: 20, top: rgb(0.12, 0.08, 0.26), bottom: rgb(0.26, 0.12, 0.30)),  // dusk
        .init(hour: 22, top: rgb(0.06, 0.07, 0.20), bottom: rgb(0.10, 0.10, 0.24)),  // night
        .init(hour: 24, top: rgb(0.04, 0.05, 0.12), bottom: rgb(0.07, 0.06, 0.18)),  // loops to 0
    ]

    static func sky(at date: Date) -> (top: Color, bottom: Color) {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date))
        let m = Double(cal.component(.minute, from: date))
        let s = Double(cal.component(.second, from: date))
        let t = h + m / 60 + s / 3600
        return interpolate(t: t)
    }

    static func interpolate(t: Double) -> (top: Color, bottom: Color) {
        let kfs = keyframes
        for i in 0..<(kfs.count - 1) {
            let a = kfs[i], b = kfs[i + 1]
            if t >= a.hour && t <= b.hour {
                let f = (t - a.hour) / max(0.0001, b.hour - a.hour)
                return (mix(a.top, b.top, f), mix(a.bottom, b.bottom, f))
            }
        }
        return (kfs[0].top, kfs[0].bottom)
    }

    // Brand accents — warm amber for "next prayer", brighter gold for iqama.
    // Both contrast on any sky color in the palette above; no greens or blues
    // (those would disappear on the daytime teal-blue keyframes).
    static let accentEmerald = rgb(1.00, 0.66, 0.32)   // amber — name kept for call-site stability
    static let accentGold    = rgb(0.99, 0.82, 0.42)   // warm gold
    static let glowSoft      = rgb(1.00, 0.94, 0.78)

    // Surface tokens.
    static let cardFill = Color.white.opacity(0.10)
    static let cardStroke = Color.white.opacity(0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textMuted = Color.white.opacity(0.50)

    // True when the sky is dark enough that stars should be visible.
    static func isNight(at date: Date) -> Bool {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date))
        let m = Double(cal.component(.minute, from: date))
        let t = h + m / 60
        return t < 5.0 || t > 19.5
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}

private func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
    let ca = a.components, cb = b.components
    let f = min(max(f, 0), 1)
    return Color(.sRGB,
                 red:   ca.r + (cb.r - ca.r) * f,
                 green: ca.g + (cb.g - ca.g) * f,
                 blue:  ca.b + (cb.b - ca.b) * f,
                 opacity: 1)
}

private extension Color {
    var components: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(AppKit)
        let n = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent), Double(n.alphaComponent))
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}
