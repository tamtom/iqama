#if os(macOS)
import SwiftUI

struct StatusBarMenuView: View {
    @StateObject private var countdownManager = CountdownManager.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let day = countdownManager.currentState?.todayPrayerTimes
            let sunrise = day?.prayerTime(for: .fajr).map { $0.addingTimeInterval(80 * 60) }
            let sunset = day?.prayerTime(for: .maghrib)
            let body = SkyGeometry.bodyNormalized(at: ctx.date, sunrise: sunrise, sunset: sunset)
            let activePrayer = countdownManager.currentState?.phase.prayer

            ZStack {
                // NSPopover already paints a vibrant material backdrop that
                // pulls in the wallpaper blur; we just tint it with the
                // time-of-day gradient at reduced opacity instead of painting
                // over it.
                CelestialBackground(
                    bodyNormalizedX: body.x,
                    bodyIsDay: body.isDay
                )
                .opacity(0.55)

                VStack(spacing: 10) {
                    header
                    SkyArcView(date: ctx.date,
                               todayPrayerTimes: day,
                               activePrayer: activePrayer,
                               bodySize: 20)
                        .frame(height: 76)
                    countdown
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    prayerList
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    footer
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 320)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                if let times = countdownManager.currentState?.todayPrayerTimes {
                    Text(times.hijriDateString)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentGold)
                .symbolEffect(.pulse, options: .repeating)
        }
    }

    // MARK: - Countdown

    private var countdown: some View {
        VStack(spacing: 6) {
            if let snapshot = countdownManager.currentState {
                let prayer = snapshot.phase.prayer
                let isIqama = snapshot.phase.isIqamaPhase

                HStack(spacing: 6) {
                    Circle()
                        .fill(isIqama ? Theme.accentGold : Theme.accentEmerald)
                        .frame(width: 6, height: 6)
                        .shadow(color: (isIqama ? Theme.accentGold : Theme.accentEmerald).opacity(0.6),
                                radius: 4)
                    Text(isIqama ? "Iqama" : prayer.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("·")
                        .foregroundStyle(Theme.textMuted)
                    Text(prayer.arabicName)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: prayer.rawValue)

                Text(snapshot.formattedTimeRemaining)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: (isIqama ? Theme.accentGold : Theme.accentEmerald).opacity(0.55),
                            radius: 10, x: 0, y: 0)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.35), value: snapshot.formattedTimeRemaining)
            } else if countdownManager.error != nil {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accentGold)
                    Text("Couldn't load prayer times")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Prayer list

    private var prayerList: some View {
        VStack(spacing: 6) {
            if let times = countdownManager.currentState?.todayPrayerTimes {
                ForEach(Prayer.orderedPrayers, id: \.self) { p in
                    row(for: p, times: times)
                }
            }
        }
    }

    private func row(for prayer: Prayer, times: DailyPrayerTimes) -> some View {
        let isCurrent = countdownManager.currentState?.phase.prayer == prayer
        let isIqama = countdownManager.currentState?.phase.isIqamaPhase ?? false
        let accent = isIqama ? Theme.accentGold : Theme.accentEmerald

        return HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? accent : Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
                .shadow(color: isCurrent ? accent.opacity(0.7) : .clear, radius: 4)

            Text(prayer.displayName)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            if let t = times.prayerTime(for: prayer) {
                Text(t, style: .time)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? accent : Theme.textSecondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open", systemImage: "rectangle.expand.vertical")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)

            Button { openSettings() } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)

            Spacer()

            Button { NSApp.terminate(nil) } label: {
                Text("Quit")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMuted)
        }
    }
}

#Preview {
    StatusBarMenuView()
        .frame(width: 300, height: 460)
}
#endif
