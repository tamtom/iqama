import SwiftUI

/// One mark on the sky arc: a prayer, the sunrise, or a point of the night.
struct SkyMark: Identifiable {
    enum Kind { case prayer(Prayer), sunrise, midnight, lastThird }
    let kind: Kind
    let time: Date
    /// The position on the arc: 0 at the start, 1 at the end. Below 0 is under the horizon.
    let t: Double

    var id: String {
        switch kind {
        case .prayer(let p): return p.rawValue
        case .sunrise: return "sunrise"
        case .midnight: return "midnight"
        case .lastThird: return "lastThird"
        }
    }

    var prayer: Prayer? {
        if case .prayer(let p) = kind { return p }
        return nil
    }

    var name: String {
        switch kind {
        case .prayer(let p): return p.displayName
        case .sunrise: return "Sunrise"
        case .midnight: return "Midnight"
        case .lastThird: return "Last third"
        }
    }
}

/// The real path of the sun for one moment, from the times of the location.
///
/// East is always on the right and west on the left, as on a map. The day arc goes from the
/// sunrise in the east (right) to Maghrib in the west (left), with Dhuhr and Asr on it. The
/// night arc goes back from Maghrib in the west (left) to Fajr in the east (right), with Isha,
/// the middle of the night, and the start of the last third on it. The
/// middle of the night is half of the time from Maghrib to Fajr, so it is at the top of the arc.
/// From Fajr to the sunrise (dawn), the sun is below the east horizon on the day arc.
struct SkyCycle {
    let isDay: Bool
    let start: Date
    let end: Date
    /// 0 at the start of the arc, 1 at the end. Below 0 at dawn, when the sun is under the horizon.
    let progress: Double

    /// The position across the screen for a position on the arc: 0 is the left end (west),
    /// 1 is the right end (east). The day arc starts on the right, the night arc on the left.
    func screenX(_ t: Double) -> Double { isDay ? 1 - t : t }
    let marks: [SkyMark]

    func t(for time: Date) -> Double {
        let span = end.timeIntervalSince(start)
        return span > 0 ? time.timeIntervalSince(start) / span : 0.5
    }

    /// Without data: Fajr 04:50, sunrise 06:10, Maghrib 18:15, Isha 19:30.
    static func at(_ date: Date, day: DailyPrayerTimes?) -> SkyCycle {
        // `day` can be the day before or after `date` (after Isha the countdown shows the next
        // day). The times change by about one minute a day, so each time moves to the day it
        // is needed on and keeps its clock time.
        let calendar = Calendar.current
        func on(_ time: Date?, _ fallbackHour: Double, dayOf ref: Date, plus days: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: ref)) ?? ref
            guard let time else { return base.addingTimeInterval(fallbackHour * 3600) }
            let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
            return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                 second: parts.second ?? 0, of: base) ?? time
        }
        let fajrTime = day?.prayerTime(for: .fajr)
        let sunriseTime = day?.sunriseTime ?? fajrTime?.addingTimeInterval(80 * 60)
        let maghribTime = day?.prayerTime(for: .maghrib)
        let ishaTime = day?.prayerTime(for: .isha)

        let fajr = on(fajrTime, 4.83, dayOf: date)
        let maghrib = on(maghribTime, 18.25, dayOf: date)

        if date >= fajr && date < maghrib {
            let sunrise = on(sunriseTime, 6.17, dayOf: date)
            var marks = [SkyMark(kind: .sunrise, time: sunrise, t: 0)]
            let span = maghrib.timeIntervalSince(sunrise)
            func t(_ time: Date) -> Double { span > 0 ? time.timeIntervalSince(sunrise) / span : 0.5 }
            for prayer in [Prayer.zuhr, .asr] {
                let time = on(day?.prayerTime(for: prayer), prayer == .zuhr ? 12.25 : 15.5, dayOf: date)
                marks.append(SkyMark(kind: .prayer(prayer), time: time, t: t(time)))
            }
            marks.append(SkyMark(kind: .prayer(.maghrib), time: maghrib, t: 1))
            // At dawn the sun is under the east horizon, and Fajr shows where it started.
            if date < sunrise {
                marks.insert(SkyMark(kind: .prayer(.fajr), time: fajr, t: t(fajr)), at: 0)
            }
            return SkyCycle(isDay: true, start: sunrise, end: maghrib, progress: t(date), marks: marks)
        }

        // The night: from Maghrib to the next Fajr.
        let evening = date >= maghrib ? date : calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let start = on(maghribTime, 18.25, dayOf: evening)
        let end = on(fajrTime, 4.83, dayOf: evening, plus: 1)
        let span = end.timeIntervalSince(start)
        func t(_ time: Date) -> Double { span > 0 ? time.timeIntervalSince(start) / span : 0.5 }
        let isha = on(ishaTime, 19.5, dayOf: evening)
        let middle = start.addingTimeInterval(span / 2)
        let lastThird = start.addingTimeInterval(span * 2 / 3)
        let marks = [
            SkyMark(kind: .prayer(.maghrib), time: start, t: 0),
            SkyMark(kind: .prayer(.isha), time: isha, t: t(isha)),
            SkyMark(kind: .midnight, time: middle, t: 0.5),
            SkyMark(kind: .lastThird, time: lastThird, t: 2.0 / 3),
            SkyMark(kind: .prayer(.fajr), time: end, t: 1),
        ]
        return SkyCycle(isDay: false, start: start, end: end, progress: t(date), marks: marks)
    }
}

// Shared geometry — used by both the arc view and the background halo so
// the warm halo in the gradient anchors to wherever the sun/moon currently is.
enum SkyGeometry {
    /// The sun or moon's position across the arc (0 at the left end, west; 1 at the right end,
    /// east) and whether it is the day arc. At dawn `x` is 1: the sun is at the east horizon.
    static func bodyNormalized(at date: Date, day: DailyPrayerTimes?) -> (x: Double, isDay: Bool) {
        let cycle = SkyCycle.at(date, day: day)
        return (x: cycle.screenX(min(max(cycle.progress, 0), 1)), isDay: cycle.isDay)
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
    /// Space between the dial and the orbit.
    var orbitGap: CGFloat = 30
    /// False in widgets: a tap there opens the app, so the sun or moon is not a button.
    var interactive = true

    @State private var travel: Double = 1
    @State private var showInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ArcContent(size: geo.size, date: date, todayPrayerTimes: todayPrayerTimes,
                       activePrayer: activePrayer, bodySize: bodySize, travel: travel,
                       orbit: orbit, orbitGap: orbitGap, interactive: interactive, showInfo: $showInfo)
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
    var orbitGap: CGFloat
    var interactive: Bool
    @Binding var showInfo: Bool

    var animatableData: Double {
        get { travel }
        set { travel = newValue }
    }

    var body: some View {
        let cycle = SkyCycle.at(date, day: todayPrayerTimes)

        // Orbit: the dial is the largest circle in the view; the arc runs outside its ring.
        let orbitRadius = min(size.width, size.height) / 2 + orbitGap
        let inset: CGFloat = orbit ? size.width / 2 - orbitRadius : 30
        let arcLeft = inset
        let arcRight = size.width - inset
        let baseY = orbit ? size.height / 2 : size.height - 14
        let peakY = orbit ? baseY - orbitRadius : 18.0

        let t = cycle.progress * travel
        let bodyPos = arcPoint(t: cycle.screenX(t), left: arcLeft, right: arcRight, base: baseY, peak: peakY)
        let glow = cycle.isDay ? Theme.accentGold : Color(red: 0.8, green: 0.86, blue: 1)
        // At dawn the sun is under the horizon. It gets brighter until the sunrise.
        let bodyOpacity = t < 0 ? max(0.35, 1 + t * 6) : 1

        ZStack {
            // 1. Dashed arc trajectory
            arcPath(from: 0, to: 1, left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                .stroke(Color.white.opacity(orbit ? 0.3 : 0.16),
                        style: StrokeStyle(lineWidth: orbit ? 1 : 0.8, lineCap: .round, dash: [2, 4]))

            // 2. The path already travelled, fading in toward the body
            arcPath(from: min(cycle.screenX(0), cycle.screenX(t)), to: max(cycle.screenX(0), cycle.screenX(t)),
                    left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                .stroke(LinearGradient(colors: [glow.opacity(0), glow.opacity(0.75)],
                                       startPoint: cycle.isDay ? .trailing : .leading,
                                       endPoint: cycle.isDay ? .leading : .trailing),
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

            // 4. West on the left and east on the right. The day goes from east to west, the
            //    night from west back to east.
            directionLabel("W", x: arcLeft, base: baseY, outward: -1)
            directionLabel("E", x: arcRight, base: baseY, outward: 1)

            // 5. The marks at their real times: the prayers, the sunrise, and the night points.
            ForEach(cycle.marks) { mark in
                let pt = arcPoint(t: cycle.screenX(mark.t), left: arcLeft, right: arcRight, base: baseY, peak: peakY)
                // Band: letters under the horizon. Orbit: letters just outside the arc.
                let angle = min(max(cycle.screenX(mark.t), -0.2), 1.2) * .pi
                let labelPos: CGPoint = orbit
                    ? CGPoint(x: size.width / 2 - (orbitRadius + 13) * cos(angle),
                              y: baseY - (orbitRadius + 13) * sin(angle))
                    : CGPoint(x: pt.x, y: min(pt.y, baseY) + 10)
                let isActive = mark.prayer != nil && mark.prayer == activePrayer
                let isPrayer = mark.prayer != nil
                Circle()
                    .fill(isActive ? Theme.accentGold : Color.white.opacity(isPrayer ? 0.55 : 0.35))
                    .frame(width: isActive ? 7 : (isPrayer ? 4 : 3), height: isActive ? 7 : (isPrayer ? 4 : 3))
                    .shadow(color: isActive ? Theme.accentGold.opacity(0.7) : .clear, radius: 6)
                    .position(pt)
                markLabel(mark, isActive: isActive)
                    .position(labelPos)
            }

            // 6. Sun / moon glyph at current position
            // Tap the sun or moon for what it shows, so the moon's phase is not read as a prayer state.
            let glyph = CelestialBodyGlyph(isDay: cycle.isDay, size: bodySize,
                                           moonPhase: todayPrayerTimes?.moonPhase ?? 0.5)
                .frame(width: bodySize, height: bodySize)
                .opacity(bodyOpacity)
            if interactive {
                Button { showInfo = true } label: {
                    glyph.contentShape(.circle.inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cycle.isDay ? "Sun" : "Moon phase")
                .popover(isPresented: $showInfo) {
                    SkyBodyInfo(cycle: cycle, day: todayPrayerTimes)
                        .presentationCompactAdaptation(.popover)
                }
                .position(bodyPos)
            } else {
                glyph.position(bodyPos)
            }
        }
    }

    private func directionLabel(_ letter: String, x: CGFloat, base: CGFloat, outward: CGFloat) -> some View {
        Text(letter)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textMuted.opacity(0.7))
            .position(orbit ? CGPoint(x: x, y: base + 14) : CGPoint(x: x + outward * 20, y: base + 1))
    }

    /// A prayer shows its first letter. The sunrise shows a symbol. The middle of the night
    /// shows "½" and the start of the last third shows "⅓".
    @ViewBuilder
    private func markLabel(_ mark: SkyMark, isActive: Bool) -> some View {
        let color = isActive ? Theme.accentGold : Theme.textMuted
        switch mark.kind {
        case .prayer(let prayer):
            Text(prayer.displayName.prefix(1))
                .font(.system(size: 9, weight: isActive ? .bold : .medium, design: .rounded))
                .foregroundStyle(color)
        case .sunrise:
            Image(systemName: "sunrise.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(color)
        case .midnight:
            Text("½")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
        case .lastThird:
            Text("⅓")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
        }
    }

    private func arcPath(from a: Double, to b: Double, left: CGFloat, right: CGFloat,
                         base: CGFloat, peak: CGFloat) -> Path {
        Path { p in
            let a = max(a, 0), b = min(b, 1)
            guard b > a else { return }
            let steps = 60
            for i in 0...steps {
                let t = a + (b - a) * Double(i) / Double(steps)
                let pt = arcPoint(t: t, left: left, right: right, base: base, peak: peak)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    /// A point on the arc. Below 0 or above 1 the point continues under the horizon, as the
    /// sun does before the sunrise.
    private func arcPoint(t: Double, left: CGFloat, right: CGFloat, base: CGFloat, peak: CGFloat) -> CGPoint {
        let clampedT = min(max(t, -0.2), 1.2)
        if orbit {
            // A true circle, which continues below the middle of the dial.
            return CGPoint(x: (left + right) / 2 - cos(clampedT * .pi) * (right - left) / 2,
                           y: base - sin(clampedT * .pi) * (base - peak))
        }
        // The band moves evenly across. Under the horizon the point stays near the end.
        let x = left + CGFloat(min(max(clampedT, -0.08), 1.08)) * (right - left)
        let y = base - sin(clampedT * .pi) * (base - peak)
        return CGPoint(x: x, y: min(y, base + 8))
    }
}

struct CelestialBodyGlyph: View {
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

/// The popover for the sun or moon on the arc: the times of the arc, and tonight's moon
/// phase by night, with a short note on what the arc shows.
private struct SkyBodyInfo: View {
    var cycle: SkyCycle
    var day: DailyPrayerTimes?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CelestialBodyGlyph(isDay: cycle.isDay, size: 26, moonPhase: day?.moonPhase ?? 0.5)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cycle.isDay ? "The sun" : MoonInfo.name(for: day?.moonPhase ?? 0.5))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(cycle.marks) { mark in
                    GridRow {
                        Text(mark.name)
                        Text(mark.time, format: .dateTime.hour().minute())
                            .monospacedDigit()
                    }
                }
            }
            .font(.system(size: 13))
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
    }

    private var subtitle: String {
        let length = cycle.end.timeIntervalSince(cycle.start)
        let hours = Int(length) / 3600, minutes = Int(length) % 3600 / 60
        if cycle.isDay { return "Daylight \(hours)h \(minutes)m" }
        guard let day else { return "Night \(hours)h \(minutes)m" }
        let lit = Int((MoonInfo.illumination(day.moonPhase) * 100).rounded())
        return "\(day.hijryDay) \(day.hijriMonthName) · \(lit)% lit · Night \(hours)h \(minutes)m"
    }

    private var note: String {
        if cycle.isDay {
            return "The sun moves on the arc from the sunrise in the east (right) to Maghrib in the west (left)."
        }
        var text = "The night arc goes back from Maghrib in the west (left) to Fajr in the east (right). "
            + "½ is the middle of the night. ⅓ is the start of the last third. "
            + "The moon shows tonight's real phase, from the Hijri date."
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
