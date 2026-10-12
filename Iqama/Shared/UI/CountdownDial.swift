import SwiftUI

/// The hero: the phase, a live countdown, and the prayer name on a soft dark glow. The time
/// of the azan or iqama is in the prayer list just below, so the hero does not repeat it.
struct CountdownDial: View {
    var prayer: Prayer
    var title: String             // "Jumu'ah" on Friday zuhr
    var isIqama: Bool
    var countdown: String
    var remaining: TimeInterval
    var live: Bool                // false: freeze per-second animation (inactive Mac window)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { isIqama ? Theme.accentGold : Theme.accentEmerald }
    private var finalMinute: Bool { remaining <= 60 }
    /// The countdown without its seconds ("1:32:46" → "1:32"), except in the final minute.
    private var rollKey: String { finalMinute ? countdown : String(countdown.dropLast(3)) }

    var body: some View {
        ZStack {
            // A soft glow without an edge, so the white digits read on a bright sky too.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.38),
                                              Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.18),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: 150))

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
                    // The digits roll when the minute changes, and each second only in the final
                    // minute. The roll blurs the large digits, so a roll every second for the
                    // whole countdown doubled the app's CPU use.
                    .animation(live ? .snappy(duration: 0.3) : nil, value: rollKey)
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
            }
            .padding(.horizontal, 36)
            .animation(.smooth(duration: 0.6), value: prayer)
            .animation(.smooth(duration: 0.6), value: isIqama)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(isIqama ? "iqama" : "azan") in \(countdown)")
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
