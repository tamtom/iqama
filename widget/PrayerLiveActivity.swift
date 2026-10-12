#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island presentation of one prayer's azan → iqama countdown. The digits
/// tick on their own via `Text(timerInterval:)`. At iqama the activity goes stale and shows
/// "Iqama now" until the app ends it.
struct PrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            let accent = context.isStale ? Theme.accentEmerald : Theme.accentGold
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "Iqama now" : "Iqama in")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(attributes.prayerName)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(attributes.prayerArabicName)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        CountdownText(state: state, isStale: context.isStale)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                            .frame(maxWidth: 110, alignment: .trailing)
                        Text(state.iqamaTime, style: .time)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(accent)
                        Text(context.isStale ? "Iqama time — line up" : "Azan at \(state.azanTime.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } compactLeading: {
                Text("\(attributes.prayerName) Iqama")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 96, alignment: .leading)
            } compactTrailing: {
                CountdownText(state: state, isStale: context.isStale)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 56, alignment: .trailing)
            } minimal: {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

/// Counts down to iqama and clamps at 0:00; shows "Now" once the activity is stale.
private struct CountdownText: View {
    let state: PrayerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("Now")
        } else {
            Text(timerInterval: state.azanTime...state.iqamaTime, countsDown: true)
                .monospacedDigit()
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<PrayerActivityAttributes>

    private var accent: Color { context.isStale ? Theme.accentEmerald : Theme.accentGold }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(context.isStale ? "IQAMA NOW" : "IQAMA IN")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.attributes.prayerName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(context.attributes.prayerArabicName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Iqama \(context.state.iqamaTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 8)

            CountdownText(state: context.state, isStale: context.isStale)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .shadow(color: accent.opacity(0.5), radius: 10)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
#endif
