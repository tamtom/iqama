import SwiftUI

// Shared geometry — used by both the arc view and the background halo so
// the warm halo in the gradient anchors to wherever the sun/moon currently is.
enum SkyGeometry {
    // Returns the celestial body's normalized x position [0,1] and whether
    // it's currently above the horizon (day) or below (night).
    static func bodyNormalized(at date: Date,
                                sunrise: Date?,
                                sunset: Date?) -> (x: Double, dayPhase: Double, isDay: Bool) {
        // dayPhase ∈ [0,1] along the visible arc (rises at sunrise → sets at sunset
        // during day; rises at sunset → sets at next sunrise during night).
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let sr = sunrise ?? cal.date(byAdding: .hour, value: 6, to: startOfDay)!
        let ss = sunset ?? cal.date(byAdding: .hour, value: 18, to: startOfDay)!

        let nowS = date.timeIntervalSinceReferenceDate
        let srS = sr.timeIntervalSinceReferenceDate
        let ssS = ss.timeIntervalSinceReferenceDate

        if nowS >= srS && nowS <= ssS {
            // Daytime
            let t = (nowS - srS) / max(60, ssS - srS)
            return (x: t, dayPhase: t, isDay: true)
        }

        // Nighttime — mirror across midnight using same sunrise/sunset for next day.
        let nextSunrise = cal.date(byAdding: .day, value: 1, to: sr)!.timeIntervalSinceReferenceDate
        let prevSunset = cal.date(byAdding: .day, value: -1, to: ss)!.timeIntervalSinceReferenceDate
        let (startS, endS): (Double, Double) = nowS < srS ? (prevSunset, srS) : (ssS, nextSunrise)
        let t = (nowS - startS) / max(60, endS - startS)
        return (x: t, dayPhase: t, isDay: false)
    }
}

// A thin band placed near the top of the window: arc trajectory, prayer tick
// marks at their real local times, and a glowing sun (day) or moon (night)
// gliding along the arc at the current position. With `animateIn`, the body rises
// from the horizon to its position when the view appears. With `orbit`, the arc is a half
// circle around the countdown dial that fills the view: it starts at the dial's middle on the
// left, goes over the top of the dial, and ends at its middle on the right.
struct SkyArcView: View {
    var date: Date
    var todayPrayerTimes: DailyPrayerTimes?
    var activePrayer: Prayer?
    var bodySize: CGFloat = 36
    var animateIn = false
    var orbit = false

    @State private var travel: Double = 1
    @State private var showInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ArcContent(size: geo.size, date: date, todayPrayerTimes: todayPrayerTimes,
                       activePrayer: activePrayer, bodySize: bodySize, travel: travel,
                       orbit: orbit, showInfo: $showInfo)
        }
        .onAppear {
            guard animateIn, !reduceMotion else { return }
            travel = 0
            withAnimation(.spring(duration: 1.8, bounce: 0.1).delay(0.15)) { travel = 1 }
        }
    }
}

private struct ArcContent: View, Animatable {
    var size: CGSize
    var date: Date
    var todayPrayerTimes: DailyPrayerTimes?
    var activePrayer: Prayer?
    var bodySize: CGFloat
    var travel: Double
    var orbit: Bool
    @Binding var showInfo: Bool

    var animatableData: Double {
        get { travel }
        set { travel = newValue }
    }

    var body: some View {
        let sunrise = todayPrayerTimes?.sunriseTime
            ?? todayPrayerTimes?.prayerTime(for: .fajr).map { addSunriseOffset(from: $0) }
            ?? defaultSunrise(date)
        let sunset = todayPrayerTimes?.prayerTime(for: .maghrib) ?? defaultSunset(date)

        // Orbit: the dial is the largest circle in the view; the arc runs outside its ring.
        let orbitRadius = min(size.width, size.height) / 2 + 30
        let inset: CGFloat = orbit ? size.width / 2 - orbitRadius : 30
        let arcLeft = inset
        let arcRight = size.width - inset
        let baseY = orbit ? size.height / 2 : size.height - 14
        let peakY = orbit ? baseY - orbitRadius : 18.0

        let body = SkyGeometry.bodyNormalized(at: date, sunrise: sunrise, sunset: sunset)
        let t = body.x * travel
        let bodyPos = arcPoint(t: t, left: arcLeft, right: arcRight, base: baseY, peak: peakY)
        let glow = body.isDay ? Theme.accentGold : Color(red: 0.8, green: 0.86, blue: 1)

        ZStack {
            // 1. Dashed arc trajectory
            arcPath(from: 0, to: 1, left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                .stroke(Color.white.opacity(orbit ? 0.3 : 0.16),
                        style: StrokeStyle(lineWidth: orbit ? 1 : 0.8, lineCap: .round, dash: [2, 4]))

            // 2. The path already travelled, fading in toward the body
            arcPath(from: 0, to: t, left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                .stroke(LinearGradient(colors: [glow.opacity(0), glow.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .shadow(color: glow.opacity(0.6), radius: 4)

            // 3. Horizon line (the band only; in the orbit it would cut through the dial)
            if !orbit {
            Path { p in
                p.move(to: CGPoint(x: arcLeft - 24, y: baseY))
                p.addLine(to: CGPoint(x: arcRight + 24, y: baseY))
            }
            .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.25), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing), lineWidth: 0.6)
            }

            // 4. Prayer ticks. Fajr comes before sunrise and Isha after sunset, so they sit on the
            //    horizon just outside the arc instead of on top of its end points.
            ForEach(Prayer.orderedPrayers, id: \.self) { prayer in
                if let azan = todayPrayerTimes?.prayerTime(for: prayer) {
                    let tick = normalize(time: azan, sunrise: sunrise, sunset: sunset)
                    let pt: CGPoint = switch prayer {
                    case .fajr: orbit ? CGPoint(x: arcLeft, y: baseY + 18) : CGPoint(x: arcLeft - 18, y: baseY)
                    case .isha: orbit ? CGPoint(x: arcRight, y: baseY + 18) : CGPoint(x: arcRight + 18, y: baseY)
                    default: arcPoint(t: tick, left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                    }
                    // Band: letters under the horizon. Orbit: letters just outside the arc.
                    let labelPos: CGPoint = if !orbit {
                        CGPoint(x: pt.x, y: baseY + 10)
                    } else if prayer == .fajr || prayer == .isha {
                        CGPoint(x: pt.x, y: pt.y + 11)
                    } else {
                        CGPoint(x: size.width / 2 - (orbitRadius + 13) * cos(tick * .pi),
                                y: baseY - (orbitRadius + 13) * sin(tick * .pi))
                    }
                    let isActive = activePrayer == prayer
                    Circle()
                        .fill(isActive ? Theme.accentGold : Color.white.opacity(0.55))
                        .frame(width: isActive ? 7 : 4, height: isActive ? 7 : 4)
                        .shadow(color: isActive ? Theme.accentGold.opacity(0.7) : .clear, radius: 6)
                        .position(pt)
                    Text(prayer.displayName.prefix(1))
                        .font(.system(size: 9, weight: isActive ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? Theme.accentGold : Theme.textMuted)
                        .position(labelPos)
                }
            }

            // 5. Sun / moon glyph at current position
            // Tap the sun or moon for what it shows, so the moon's phase is not read as a prayer state.
            Button { showInfo = true } label: {
                CelestialBodyGlyph(isDay: body.isDay, size: bodySize, moonPhase: todayPrayerTimes?.moonPhase ?? 0.5)
                    .frame(width: bodySize, height: bodySize)
                    .contentShape(.circle.inset(by: -6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(body.isDay ? "Sun" : "Moon phase")
            .popover(isPresented: $showInfo) {
                SkyBodyInfo(isDay: body.isDay, day: todayPrayerTimes, sunrise: sunrise, sunset: sunset)
                    .presentationCompactAdaptation(.popover)
            }
            .position(bodyPos)
        }
    }

    private func arcPath(from a: Double, to b: Double, left: CGFloat, right: CGFloat,
                         base: CGFloat, peak: CGFloat) -> Path {
        Path { p in
            guard b > a else { return }
            let steps = 60
            for i in 0...steps {
                let t = a + (b - a) * Double(i) / Double(steps)
                let pt = arcPoint(t: t, left: left, right: right, base: base, peak: peak)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func arcPoint(t: Double, left: CGFloat, right: CGFloat, base: CGFloat, peak: CGFloat) -> CGPoint {
        let clampedT = min(max(t, 0), 1)
        // The band moves evenly across; the orbit follows a true half circle.
        let x = orbit
            ? (left + right) / 2 - cos(clampedT * .pi) * (right - left) / 2
            : left + CGFloat(clampedT) * (right - left)
        let y = base - sin(clampedT * .pi) * (base - peak)
        return CGPoint(x: x, y: y)
    }

    private func normalize(time: Date, sunrise: Date, sunset: Date) -> Double {
        let span = sunset.timeIntervalSince(sunrise)
        guard span > 0 else { return 0.5 }
        return min(max(time.timeIntervalSince(sunrise) / span, 0), 1)
    }

    // Awqaf "fajr" is dawn / first light; actual sunrise is ~80 min later.
    // For arc geometry we want astronomical sunrise. Approximate using
    // shurooq if available via the data fields — fall back to fajr + 80m.
    private func addSunriseOffset(from fajr: Date) -> Date {
        fajr.addingTimeInterval(80 * 60)
    }

    private func defaultSunrise(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 6, minute: 0, second: 0, of: d) ?? d
    }
    private func defaultSunset(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 18, minute: 30, second: 0, of: d) ?? d
    }
}

private struct CelestialBodyGlyph: View {
    let isDay: Bool
    var size: CGFloat
    var moonPhase: Double = 0.5

    var body: some View {
        if isDay {
            // Sun: a white-hot core in a wide soft glow, with a faint 22° halo ring.
            let d = size
            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.98, blue: 0.88),
                                              Color(red: 1, green: 0.90, blue: 0.62)],
                                     center: .center, startRadius: 0, endRadius: d * 0.5))
                .frame(width: d, height: d)
                .shadow(color: .white.opacity(0.9), radius: d * 0.35)
                .shadow(color: Color(red: 1, green: 0.9, blue: 0.6).opacity(0.6), radius: d * 0.9)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.12), .clear],
                                             center: .center, startRadius: d * 0.3, endRadius: d * 1.9))
                        .frame(width: d * 3.8, height: d * 3.8)
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: ([.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red] as [Color])
                                .map { $0.opacity(0.22) }, center: .center),
                            lineWidth: d * 0.12)
                        .blur(radius: d * 0.08)
                        .frame(width: d * 3.0, height: d * 3.0)
                }
        } else {
            // Moon in tonight's real phase, from the Hijri day. Near the new moon the lit part
            // is too thin to see, so the crescent keeps a minimum width, and the dark part
            // shows faint earthshine.
            let d = size
            let lit = min(max(moonPhase - floor(moonPhase), 0.09), 0.91)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.62, green: 0.68, blue: 0.85).opacity(0.5),
                                                  Color(red: 0.42, green: 0.48, blue: 0.66).opacity(0.38)],
                                         center: .init(x: 0.4, y: 0.4), startRadius: 0, endRadius: d * 0.5))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.7))
                MoonLitShape(phase: lit)
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.99, green: 0.98, blue: 0.94),
                                     Color(red: 0.82, green: 0.84, blue: 0.93)],
                            center: .init(x: 0.4, y: 0.4), startRadius: 1, endRadius: d * 0.5
                        )
                    )
                    .shadow(color: .white.opacity(0.8), radius: 3)
            }
            .frame(width: d, height: d)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.8, green: 0.86, blue: 1).opacity(0.35), .clear],
                                         center: .center, startRadius: d * 0.4, endRadius: d * 1.4))
                    .frame(width: d * 2.8, height: d * 2.8)
            }
        }
    }
}

/// The lit part of the moon for a phase in 0…1 (0 = new, 0.5 = full). The terminator is a
/// half-ellipse whose width follows the cosine of the phase angle.
struct MoonLitShape: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let p = phase - floor(phase)
        let waxing = p < 0.5
        let k = cos(2 * .pi * p)           // 1 at new, -1 at full
        var path = Path()
        // Bright limb: right half while waxing, left half while waning.
        path.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !waxing)
        // Terminator back to the top.
        let steps = 40
        for i in 0...steps {
            let a = Double.pi / 2 - Double.pi * Double(i) / Double(steps)   // +90° → -90°
            let x = c.x + (waxing ? -1 : 1) * CGFloat(k) * r * CGFloat(cos(a)) * -1
            let y = c.y + r * CGFloat(sin(a))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// The popover for the sun or moon on the arc: sunrise and sunset by day, and tonight's moon
/// phase by night, with a short note on what the arc shows.
private struct SkyBodyInfo: View {
    var isDay: Bool
    var day: DailyPrayerTimes?
    var sunrise: Date
    var sunset: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CelestialBodyGlyph(isDay: isDay, size: 26, moonPhase: day?.moonPhase ?? 0.5)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDay ? "The sun" : MoonInfo.name(for: day?.moonPhase ?? 0.5))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
    }

    private var subtitle: String {
        if isDay {
            let length = sunset.timeIntervalSince(sunrise)
            let hours = Int(length) / 3600, minutes = Int(length) % 3600 / 60
            return "Sunrise \(sunrise.formatted(date: .omitted, time: .shortened)) · "
                + "Sunset \(sunset.formatted(date: .omitted, time: .shortened)) · \(hours)h \(minutes)m"
        }
        guard let day else { return "" }
        let lit = Int((MoonInfo.illumination(day.moonPhase) * 100).rounded())
        return "\(day.hijryDay) \(day.hijriMonthName) · \(lit)% lit"
    }

    private var note: String {
        if isDay {
            return "The sun moves along the arc from sunrise to sunset. The dots on the arc are today's prayer times."
        }
        var text = "The moon shows tonight's real phase, from the Hijri date. It does not show a prayer state."
        if let day {
            let phase = day.moonPhase
            if phase < 0.04 || phase > 0.96 {
                text += " Near the new moon it is hard to see, so the app draws a thin crescent."
            }
            if day.hijryDay < 14 {
                let days = 14 - day.hijryDay
                text += " Full moon in \(days) \(days == 1 ? "day" : "days")."
            } else if day.hijryDay > 16 {
                text += " A new Hijri month starts in about \(max(1, 30 - day.hijryDay)) days."
            }
        }
        return text
    }
}

enum MoonInfo {
    /// The lit fraction of the disc for a phase in 0…1 (0 = new, 0.5 = full).
    static func illumination(_ phase: Double) -> Double {
        (1 - cos(2 * .pi * phase)) / 2
    }

    static func name(for phase: Double) -> String {
        let p = phase - floor(phase)
        switch p {
        case ..<0.04: return "New moon"
        case ..<0.22: return "Waxing crescent"
        case ..<0.28: return "First quarter"
        case ..<0.47: return "Waxing gibbous"
        case ..<0.53: return "Full moon"
        case ..<0.72: return "Waning gibbous"
        case ..<0.78: return "Last quarter"
        case ..<0.96: return "Waning crescent"
        default: return "New moon"
        }
    }
}
