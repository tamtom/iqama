#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island presentation of the prayer countdown. The countdown digits
/// tick on their own via `Text(_:style:.timer)`, so the app only pushes a new content state
/// when the phase flips.
struct PrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let accent = state.isIqama ? Theme.accentGold : Theme.accentEmerald
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.isIqama ? "Iqama" : "Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(state.prayerName)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(state.prayerArabicName)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: state.countdown, countsDown: true)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                            .frame(maxWidth: 110, alignment: .trailing)
                        Text(state.azanTime, style: .time)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: state.isIqama ? "person.3.fill" : "moon.stars.fill")
                            .foregroundStyle(accent)
                        Text(state.isIqama
                             ? "Iqama in progress — line up"
                             : "Iqama \(state.iqamaLeadMinutes)m after azan")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } compactLeading: {
                // Menu-bar-style phase text: "Asr" while waiting for azan, "Asr Iqama" after.
                Text(state.isIqama ? "\(state.prayerName) Iqama" : state.prayerName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 96, alignment: .leading)
            } compactTrailing: {
                Text(timerInterval: state.countdown, countsDown: true)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: 56, alignment: .trailing)
            } minimal: {
                // Truly tiny — phase conveyed by icon (moon = azan, congregation = iqama) + tint.
                Image(systemName: state.isIqama ? "person.3.fill" : "moon.stars.fill")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<PrayerActivityAttributes>

    private var accent: Color { context.state.isIqama ? Theme.accentGold : Theme.accentEmerald }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(context.state.isIqama ? "IQAMA TIME" : "NEXT PRAYER")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.state.prayerName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(context.state.prayerArabicName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(context.state.azanTime, style: .time)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 8)

            Text(timerInterval: context.state.countdown, countsDown: true)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .shadow(color: accent.opacity(0.5), radius: 10)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private extension PrayerActivityAttributes.ContentState {
    /// An interval ending at the target so `Text(timerInterval:countsDown:)` counts down and
    /// clamps at 0:00 — instead of `.timer` style flipping to a count-up once the target passes.
    /// The lower bound is well in the past (no single prayer gap approaches 24h), so it only
    /// bounds the interval; the displayed value is always `target − now`.
    var countdown: ClosedRange<Date> {
        targetTime.addingTimeInterval(-86_400)...targetTime
    }
}
#endif
