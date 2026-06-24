//
//  ContentView.swift
//  Dubai iqama
//

import SwiftUI

struct ContentView: View {
    @StateObject private var countdownManager = CountdownManager.shared
    @ObservedObject private var checkIn = NotificationManager.shared
    #if os(macOS)
    @StateObject private var updateChecker = UpdateChecker.shared
    @Environment(\.openSettings) private var openSettings
    // When the window isn't key/active, suppress the per-second countdown
    // animation. The `.numericText()` content transition interpolates the entire
    // glass display list at the display refresh rate every time the seconds tick,
    // which kept the app pinning the CPU even while backgrounded (confirmed via
    // `sample`: InterpolatedDisplayList / rewriteInterpolation). When inactive we
    // snap the value and show it at minute resolution, so a backgrounded window
    // does effectively no rendering work between minutes.
    @Environment(\.controlActiveState) private var controlActiveState
    private var windowActive: Bool { controlActiveState != .inactive }
    #else
    // iOS has no Settings scene / menu bar — present settings as a sheet instead.
    @State private var showSettings = false
    // iOS suspends backgrounded apps, so there's nothing to gate.
    private var windowActive: Bool { true }
    #endif

    @AppStorage(AppSettings.Keys.locationConfirmed, store: AppSettings.shared)
    private var locationConfirmed = false
    @State private var showLocationSetup = false

    // Prayer check-in
    @AppStorage(AppSettings.Keys.checkInOnboarded) private var checkInOnboarded = false
    @State private var showCheckInSetup = false
    @AppStorage(AppSettings.Keys.nagFajr) private var nagFajr = AppSettings.Defaults.nagFajr
    @AppStorage(AppSettings.Keys.nagZuhr) private var nagZuhr = AppSettings.Defaults.nagZuhr
    @AppStorage(AppSettings.Keys.nagAsr) private var nagAsr = AppSettings.Defaults.nagAsr
    @AppStorage(AppSettings.Keys.nagMaghrib) private var nagMaghrib = AppSettings.Defaults.nagMaghrib
    @AppStorage(AppSettings.Keys.nagIsha) private var nagIsha = AppSettings.Defaults.nagIsha
    @AppStorage(AppSettings.Keys.nagIntervalMinutes) private var nagInterval = AppSettings.Defaults.nagIntervalMinutes
    @AppStorage(AppSettings.Keys.notificationsEnabled) private var notificationsEnabled = AppSettings.Defaults.notificationsEnabled

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let day = countdownManager.currentState?.todayPrayerTimes
            let sunrise = day?.prayerTime(for: .fajr).map { $0.addingTimeInterval(80 * 60) }
            let sunset = day?.prayerTime(for: .maghrib)
            let body = SkyGeometry.bodyNormalized(at: now, sunrise: sunrise, sunset: sunset)

            ZStack {
                #if os(macOS)
                // 1. Window-level wallpaper blur (the macOS Tahoe glass).
                WindowBackdrop(material: .hudWindow)
                    .ignoresSafeArea()

                // 2. Celestial gradient tints the blurred wallpaper with the
                //    time-of-day mood without fully blocking it.
                CelestialBackground(
                    timeOverride: nil,
                    bodyNormalizedX: body.x,
                    bodyIsDay: body.isDay
                )
                .opacity(0.55)
                .backgroundExtensionEffect()
                .ignoresSafeArea()

                // 3. AppKit interop: make the host NSWindow transparent.
                WindowTransparencyConfigurator()
                    .frame(width: 0, height: 0)
                #else
                // iOS has no desktop wallpaper to blur — paint the celestial sky
                // straight onto a dark base so it reads fully on its own.
                Color.black.ignoresSafeArea()
                CelestialBackground(
                    timeOverride: nil,
                    bodyNormalizedX: body.x,
                    bodyIsDay: body.isDay
                )
                .ignoresSafeArea()
                #endif

                ScrollView {
                    VStack(spacing: 18) {
                        #if os(macOS)
                        if let update = updateChecker.availableUpdate {
                            UpdateBanner(update: update)
                        }
                        #endif

                        header

                        SkyArcView(date: now,
                                   todayPrayerTimes: day,
                                   activePrayer: effectivePrayer)
                            .frame(height: 110)

                        countdownCard

                        if let pending = checkIn.pendingCheckIn {
                            checkInPendingCard(pending)
                        }

                        prayerRail

                        checkInCTACard

                        footer
                    }
                    .padding(.horizontal, 32)
                    #if os(macOS)
                    .padding(.top, 60)           // clear the macOS 26 window controls
                    #else
                    .padding(.top, 12)           // safe area handles the notch on iOS
                    #endif
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
        .preferredColorScheme(.dark)
        .onAppear {
            countdownManager.refresh()
            if !locationConfirmed {
                showLocationSetup = true
            } else if !checkInOnboarded {
                showCheckInSetup = true
            }
        }
        .sheet(isPresented: $showLocationSetup, onDismiss: {
            // First-run funnel: location first, then introduce Prayer Check-in.
            if !checkInOnboarded { showCheckInSetup = true }
        }) {
            LocationSetupView()
        }
        .sheet(isPresented: $showCheckInSetup) {
            CheckInSetupView()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Iqama")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, d MMMM"
        var s = df.string(from: Date())
        if let h = countdownManager.currentState?.todayPrayerTimes?.hijriDateString {
            s += " · " + h
        }
        return s
    }

    // MARK: - Countdown card

    private var countdownCard: some View {
        Group {
            if let snapshot = countdownManager.currentState {
                countdownBody(
                    prayer: snapshot.phase.prayer,
                    isIqama: snapshot.phase.isIqamaPhase,
                    // Live seconds only while the window is being looked at; a
                    // backgrounded window shows a static minute-resolution value
                    // so the second-by-second string churn (and its display-list
                    // interpolation) stops entirely.
                    countdownText: windowActive ? snapshot.formattedTimeRemaining : snapshot.shortFormattedTime,
                    day: snapshot.todayPrayerTimes,
                    settings: snapshot.azanSettings
                )
            } else if countdownManager.error != nil {
                errorBody
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var effectivePrayer: Prayer? { countdownManager.currentState?.phase.prayer }
    private var effectiveIsIqama: Bool { countdownManager.currentState?.phase.isIqamaPhase ?? false }

    @ViewBuilder
    private func countdownBody(prayer: Prayer, isIqama: Bool, countdownText: String,
                                day: DailyPrayerTimes?, settings: AzanSettings?) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                PulsingDot(color: isIqama ? Theme.accentGold : Theme.accentEmerald)
                Text(isIqama ? "Iqama time" : "Next prayer")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prayer.displayName)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(prayer.arabicName)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            .contentTransition(.opacity)
            .animation(windowActive ? .easeInOut(duration: 0.4) : nil, value: prayer.rawValue)

            Text(countdownText)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: (isIqama ? Theme.accentGold : Theme.accentEmerald).opacity(0.55),
                        radius: 14, x: 0, y: 0)
                .contentTransition(.numericText())
                .animation(windowActive ? .spring(duration: 0.35) : nil, value: countdownText)

            if let day, let azan = day.prayerTime(for: prayer) {
                HStack(spacing: 12) {
                    Label {
                        Text(azan, style: .time)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "sun.haze")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                    if !isIqama, let settings {
                        let iqamaMin = settings.iqamaMinutes(for: prayer, isFriday: day.isFriday)
                        Text("·")
                            .foregroundStyle(Theme.textMuted)
                        Label("Iqama +\(iqamaMin)m", systemImage: "person.3.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var errorBody: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accentGold)
            Text("Unable to load prayer times")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button("Retry") { countdownManager.refresh() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentEmerald)
        }
    }

    // MARK: - Prayer check-in

    /// Live, unanswered check-in: the in-app twin of the notification, with the answers
    /// inline (banners vanish in seconds unless the user switched the style to Alerts).
    @ViewBuilder
    private func checkInPendingCard(_ pending: NotificationManager.CheckInState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pending.awaitingConfirmation ? "questionmark.circle.fill" : "figure.walk.motion")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accentGold)

            VStack(alignment: .leading, spacing: 1) {
                Text(pending.awaitingConfirmation
                     ? "Did you pray \(pending.prayer.displayName)?"
                     : "\(pending.prayer.displayName) iqama is coming up")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(pending.awaitingConfirmation
                     ? "Confirm to stop the reminders."
                     : "Commit now and the check-in stands down.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button("Later") { checkIn.snoozeCheckIn() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Button(pending.awaitingConfirmation ? "Yes, Wallah" : "Wallah, going now") {
                checkIn.confirmPrayed()
            }
            .buttonStyle(.glass(Glass.regular.tint(Theme.accentGold).interactive()))
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.25), value: pending)
    }

    /// Main entry point for the feature: shows its live status, opens the onboarding sheet.
    private var checkInCTACard: some View {
        Button { showCheckInSetup = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accentGold)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Prayer Check-in")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(checkInStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var checkInStatusText: String {
        if !checkInOnboarded { return "Set up “Did you pray?” follow-ups" }
        let enabled = [(nagFajr, "Fajr"), (nagZuhr, "Dhuhr"), (nagAsr, "Asr"),
                       (nagMaghrib, "Maghrib"), (nagIsha, "Isha")]
            .filter(\.0).map(\.1)
        if enabled.isEmpty || !notificationsEnabled { return "Off" }
        return enabled.joined(separator: ", ") + " · every \(nagInterval) min"
    }

    // MARK: - Prayer rail

    private var prayerRail: some View {
        VStack(spacing: 0) {
            ForEach(Prayer.orderedPrayers, id: \.self) { prayer in
                prayerRow(prayer: prayer)
                if prayer != .isha {
                    Rectangle()
                        .fill(Theme.cardStroke)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func prayerRow(prayer: Prayer) -> some View {
        let isCurrent = effectivePrayer == prayer
        let times = countdownManager.currentState?.todayPrayerTimes
        let settings = countdownManager.currentState?.azanSettings
        let isIqamaPhase = effectiveIsIqama

        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.cardStroke, lineWidth: 1)
                    .frame(width: 22, height: 22)
                if isCurrent {
                    Circle()
                        .fill(isIqamaPhase ? Theme.accentGold : Theme.accentEmerald)
                        .frame(width: 10, height: 10)
                        .shadow(color: (isIqamaPhase ? Theme.accentGold : Theme.accentEmerald).opacity(0.7),
                                radius: 8, x: 0, y: 0)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(prayer.displayName)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(prayer.arabicName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            if let times, let settings, let azan = times.prayerTime(for: prayer) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(azan, style: .time)
                        .font(.system(size: 14, weight: isCurrent ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? (isIqamaPhase ? Theme.accentGold : Theme.accentEmerald) : Theme.textPrimary)
                    let iqamaMin = settings.iqamaMinutes(for: prayer, isFriday: times.isFriday)
                    Text("+\(iqamaMin)m")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isCurrent ? Color.white.opacity(0.06) : .clear)
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(locationText)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)

            Spacer()

            Button {
                #if os(macOS)
                openSettings()
                #else
                showSettings = true
                #endif
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var locationText: String {
        if let t = countdownManager.currentState?.todayPrayerTimes {
            return "\(t.areaNameEn) · \(t.emirateNameEn)"
        }
        return "Locating…"
    }
}

private struct PulsingDot: View {
    var color: Color
    @State private var on = false
    // A `repeatForever` animation keeps the render server busy indefinitely, even
    // when the window is backgrounded. Gate it on the active state so it settles to
    // a static dot the moment the window loses focus (macOS) / the app backgrounds (iOS).
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    private var isActive: Bool { controlActiveState != .inactive }
    #else
    @Environment(\.scenePhase) private var scenePhase
    private var isActive: Bool { scenePhase == .active }
    #endif

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: on ? 6 : 2)
            .opacity(on ? 1.0 : 0.65)
            .onAppear { setPulsing(isActive) }
            #if os(macOS)
            .onChange(of: controlActiveState) { _, state in setPulsing(state != .inactive) }
            #else
            .onChange(of: scenePhase) { _, phase in setPulsing(phase == .active) }
            #endif
    }

    private func setPulsing(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                on = true
            }
        } else {
            // A finite animation here replaces the repeating one, letting it stop.
            withAnimation(.easeInOut(duration: 0.3)) {
                on = false
            }
        }
    }
}

#if os(macOS)
// Slim banner shown at the top of the window when a newer release exists on
// GitHub. "Update" downloads the DMG, verifies it, swaps the app bundle, and
// relaunches — all in-app.
struct UpdateBanner: View {
    let update: UpdateChecker.UpdateInfo
    @StateObject private var installer = UpdateInstaller.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentGold)
                .symbolEffect(.pulse, options: .repeating, isActive: installer.isWorking)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if installer.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accentGold)
            } else {
                Button(buttonLabel) { installer.install(update) }
                    .buttonStyle(.glass(Glass.regular.tint(Theme.accentGold).interactive()))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: installer.phase)
    }

    private var statusIcon: String {
        switch installer.phase {
        case .failed: return "exclamationmark.triangle.fill"
        default:      return "arrow.down.circle.fill"
        }
    }

    private var statusTitle: String {
        switch installer.phase {
        case .downloading: return "Downloading update…"
        case .verifying:   return "Verifying…"
        case .installing:  return "Installing — app will relaunch"
        case .failed:      return "Update failed"
        case .idle:        return "Update available"
        }
    }

    private var statusDetail: String {
        switch installer.phase {
        case .downloading(let p): return "\(Int(p * 100))% of Iqama \(update.version)"
        case .verifying:          return "Checking Apple notarization…"
        case .installing:         return "Swapping in the new version…"
        case .failed(let msg):    return msg
        case .idle:               return "Iqama \(update.version) is ready to install."
        }
    }

    private var buttonLabel: String {
        if case .failed = installer.phase { return "Retry" }
        return "Update"
    }
}
#endif

#Preview {
    ContentView()
}
