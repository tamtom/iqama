import SwiftUI

/// The hero: a ring that fills from the previous prayer event to the next one, with the
/// prayer name and a live countdown inside.
struct CountdownDial: View {
    var prayer: Prayer
    var title: String             // "Jumu'ah" on Friday zuhr
    var isIqama: Bool
    var progress: Double          // 0…1 of the current interval
    var countdown: String
    var remaining: TimeInterval
    var targetTime: Date
    var live: Bool                // false: freeze per-second animation (inactive Mac window)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var accent: Color { isIqama ? Theme.accentGold : Theme.accentEmerald }
    private var finalMinute: Bool { remaining <= 60 }

    var body: some View {
        ZStack {
            // A new phase gets a new ring, so the arc never unwinds from full back to empty.
            DialRing(progress: appeared ? progress : 0, accent: accent)
                .animation(reduceMotion ? nil : .spring(duration: 1.4, bounce: 0.15), value: appeared)
                .animation(live ? .linear(duration: 1) : nil, value: progress)
                .id("\(prayer.rawValue)|\(isIqama)")
                .transition(.opacity)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    LiveDot(color: accent)
                    Text(isIqama ? "Iqama in" : "Azan in")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(countdown)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(finalMinute ? accent : .white)
                    .shadow(color: accent.opacity(finalMinute ? 0.9 : 0.6), radius: finalMinute ? 24 : 18)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.6), value: finalMinute)
                    .animation(live ? .snappy(duration: 0.3) : nil, value: countdown)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(prayer.arabicName)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.textPrimary)
                .id(prayer)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.9)))

                Text("\(isIqama ? "Iqama" : "Azan") at \(targetTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textMuted)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 36)
            .animation(.smooth(duration: 0.6), value: prayer)
            .animation(.smooth(duration: 0.6), value: isIqama)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(isIqama ? "iqama" : "azan") in \(countdown)")
    }
}

/// Track, minute ticks, the progress arc, and a glowing head at its tip.
private struct DialRing: View, Animatable {
    var progress: Double
    var accent: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line: CGFloat = 9
            let radius = size / 2 - line
            let clamped = min(max(progress, 0), 1)
            ZStack {
                // Soft inner disc so the digits sit on a calm surface.
                // Calm, dark-blue disc so the white digits read on a bright daytime sky too.
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.42),
                                                  Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.16)],
                                         center: .center, startRadius: 0, endRadius: radius))
                    .padding(line * 1.5)

                Ticks(count: 60)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .padding(line * 2.2)

                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: line)
                    .padding(line / 2)

                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(colors: [accent.opacity(0.25), accent, Theme.glowSoft],
                                        center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(clamped, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(line / 2)
                    .shadow(color: accent.opacity(0.55), radius: 10)

                // Head of the arc.
                let angle = Angle.degrees(360 * clamped - 90)
                Circle()
                    .fill(Theme.glowSoft)
                    .frame(width: line * 1.6, height: line * 1.6)
                    .shadow(color: accent, radius: 10)
                    .shadow(color: accent.opacity(0.6), radius: 22)
                    .offset(x: cos(angle.radians) * (size / 2 - line),
                            y: sin(angle.radians) * (size / 2 - line))
                    .opacity(clamped > 0.005 ? 1 : 0)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Ticks: Shape {
    var count: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            let inner = r - (i % 5 == 0 ? 7 : 3.5)
            p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        return p
    }
}

/// A small breathing dot. A `repeatForever` animation keeps the render server busy, so it
/// runs only while the window or app is active, and never with Reduce Motion.
struct LiveDot: View {
    var color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    private var active: Bool { controlActiveState != .inactive }
    #else
    @Environment(\.scenePhase) private var scenePhase
    private var active: Bool { scenePhase == .active }
    #endif

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: on ? 6 : 2)
            .opacity(on ? 1.0 : 0.6)
            .onAppear { setPulsing(active) }
            .onChange(of: active) { _, value in setPulsing(value) }
    }

    private func setPulsing(_ value: Bool) {
        if value && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
        } else {
            // A finite animation replaces the repeating one, so it stops.
            withAnimation(.easeInOut(duration: 0.3)) { on = true }
        }
    }
}
