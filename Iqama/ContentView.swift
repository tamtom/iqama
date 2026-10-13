//
//  ContentView.swift
//  Dubai iqama
//

import SwiftUI

struct ContentView: View {
    @StateObject private var countdownManager = CountdownManager.shared
    @ObservedObject private var checkIn = NotificationManager.shared
    @ObservedObject private var adhan = AdhanPlayer.shared
    #if os(macOS)
    @StateObject private var updateChecker = UpdateChecker.shared
    @Environment(\.openSettings) private var openSettingsAction
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
    @AppStorage(AppSettings.Keys.ramadanMode, store: AppSettings.shared)
    private var ramadanMode = AppSettings.Defaults.ramadanMode
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
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

    @Namespace private var dockNamespace
    @State private var burst = 0
    @State private var lastPhaseKey = ""
    @State private var scrollPosition = ScrollPosition()
    @State private var showTimePreview = false
    @State private var hingePartiallyOpen = false
    private let previewClock = PreviewClock.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date.addingTimeInterval(previewClock.offset)
            let day = countdownManager.currentState?.todayPrayerTimes
            let sunrise = day?.sunriseTime ?? day?.prayerTime(for: .fajr).map { $0.addingTimeInterval(80 * 60) }
            let sunset = day?.prayerTime(for: .maghrib)
            let asr = day?.prayerTime(for: .asr)
            let body = SkyGeometry.bodyNormalized(at: now, day: day)
            let sky = SkyState(now: now, day: day, sunrise: sunrise, sunset: sunset, asr: asr,
                               lightX: body.isDay ? 0.5 - 0.5 * cos(body.x * .pi) : 0.5,
                               ground: SkyPalette.colors(at: now, sunrise: sunrise, sunset: sunset, asr: asr).groundColor,
                               ramadan: RamadanStatus.at(now, day: day,
                                                         mode: AppSettings.RamadanMode(rawValue: ramadanMode) ?? .auto))

            ZStack {
                #if os(macOS)
                // 1. Window-level wallpaper blur (the macOS Tahoe glass).
                WindowBackdrop(material: .hudWindow)
                    .ignoresSafeArea()

                // 2. The living sky tints the blurred wallpaper without fully blocking it.
                SkyScene(bodyNormalizedX: body.x, bodyIsDay: body.isDay, sunrise: sunrise, sunset: sunset, asr: asr)
                    .opacity(0.7)
                    .ignoresSafeArea()

                // 3. AppKit interop: make the host NSWindow transparent.
                WindowTransparencyConfigurator()
                    .frame(width: 0, height: 0)

                stackedLayout(sky)
                #else
                Color.black.ignoresSafeArea()
                SkyScene(bodyNormalizedX: body.x, bodyIsDay: body.isDay, sunrise: sunrise, sunset: sunset, asr: asr)
                    .ignoresSafeArea()

                // A wide screen (the inner display of iPhone Duo, an iPad in landscape) shows
                // two columns. A tall screen shows one column that scrolls.
                // iPhone Duo half open with the fold across the screen is the tabletop pose: the
                // fold becomes the horizon of the sea.
                GeometryReader { geo in
                    let fold = Self.fold(in: geo)
                    if let horizon = tabletopHorizon(fold, geo) {
                        tabletopLayout(sky, horizon: horizon, safeTop: geo.safeAreaInsets.top)
                    } else if horizontalSizeClass == .regular && geo.size.width > geo.size.height * 1.15 {
                        wideLayout(sky, fold: fold.flatMap { $0.height > $0.width ? $0 : nil })
                    } else {
                        stackedLayout(sky)
                    }
                }
                .modifier(HingeObserver(partiallyOpen: $hingePartiallyOpen))

                #if DEBUG
                if UserDefaults.standard.bool(forKey: "seaPreview") {
                    seaPreview(now, day: day)
                }
                #endif
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: burst)
        .sensoryFeedback(trigger: checkIn.pendingCheckIn) { old, new in
            // Answering a check-in clears it: confirm with a tap of success.
            old != nil && new == nil ? .success : nil
        }
        .task { await previewClock.checkAvailability() }
        .onChange(of: phaseKey) { old, new in
            // Celebrate a real azan / iqama transition, not the first value after launch.
            if !old.isEmpty, !new.isEmpty { burst += 1 }
        }
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

    #if DEBUG && os(iOS)
    /// A test of the tabletop sea: `-seaPreview YES` shows it full screen with the horizon at the
    /// middle. `-seaClock HH:mm` sets the time of the day.
    private func seaPreview(_ now: Date, day: DailyPrayerTimes?) -> some View {
        var date = now
        if let clock = UserDefaults.standard.string(forKey: "seaClock") {
            let parts = clock.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) ?? now
            }
        }
        let latitude = AppSettings.selectedLatitude ?? AppSettings.selectedEmirate.latitude
        return GeometryReader { geo in
            SeaHorizonView(date: date, day: day, latitude: latitude, foldY: geo.size.height / 2)
        }
        .ignoresSafeArea()
    }
    #endif

    /// The values that one update of the sky gives to the layouts.
    private struct SkyState {
        let now: Date
        let day: DailyPrayerTimes?
        let sunrise: Date?
        let sunset: Date?
        let asr: Date?
        /// 0 = the sun is at the left, 1 = at the right.
        let lightX: Double
        let ground: Color
        let ramadan: RamadanStatus?
    }

    // MARK: - Layouts

    /// One column that scrolls: the iPhone, the outer display of iPhone Duo, and the Mac.
    private func stackedLayout(_ sky: SkyState) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(macOS)
                if let update = updateChecker.availableUpdate {
                    UpdateBanner(update: update)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                #endif

                header(sky.ramadan)
                    .padding(.horizontal, 28)
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.3)
                    }

                // The sun or moon orbits the countdown dial, from its middle on the
                // left, over the top, to its middle on the right.
                hero(sky.ramadan)
                    .padding(.horizontal, 64)
                    .background {
                        SkyArcView(date: sky.now,
                                   todayPrayerTimes: sky.day,
                                   activePrayer: effectivePrayer,
                                   animateIn: true,
                                   orbit: true)
                            .padding(.horizontal, 64)
                    }
                    .padding(.top, 64)
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            .scaleEffect(phase.value < 0 ? 0.88 : 1)
                            .opacity(phase.value < 0 ? 0.35 : 1)
                    }
                    .zIndex(1)

                if let ramadan = sky.ramadan {
                    RamadanCard(status: ramadan, clockOffset: previewClock.offset)
                        .padding(.horizontal, 24)
                        // The skyline below moves up by 36 points. This space keeps it off the card.
                        .padding(.bottom, 40)
                        .zIndex(1)
                }

                HorizonView(date: sky.now, sunrise: sky.sunrise, sunset: sky.sunset, asr: sky.asr,
                            lightX: sky.lightX)
                    .padding(.top, -36)

                PrayerTimeline(day: sky.day,
                               settings: countdownManager.currentState?.azanSettings,
                               activePrayer: effectivePrayer,
                               isIqamaPhase: effectiveIsIqama,
                               now: sky.now)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    // The ground under the skyline continues past the end of the content,
                    // so a bounce at the bottom never shows sky below the land.
                    .background(alignment: .top) {
                        sky.ground.padding(.bottom, -1200)
                    }
            }
            #if os(macOS)
            .padding(.top, 52)           // clear the macOS 26 window controls
            #else
            .padding(.top, 8)            // safe area handles the notch on iOS
            #endif
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .bottom) { dock }
        .scrollPosition($scrollPosition)
        .onChange(of: effectivePrayer, initial: true) { _, prayer in
            scrollToActive(prayer)
        }
        .onChange(of: showTimePreview) { _, shown in
            // The preview panel is tall: keep the dial in view above it.
            if shown { withAnimation(.spring(duration: 0.6)) { scrollPosition.scrollTo(edge: .top) } }
            else { scrollToActive(effectivePrayer) }
        }
    }

    #if os(iOS)
    /// Two columns, one in each half of a wide screen. On the inner display of iPhone Duo the
    /// fold is between the columns, so no text and no control is on the fold.
    private func wideLayout(_ sky: SkyState, fold: CGRect?) -> some View {
        // With a real fold, the left column ends at the fold and the right column starts after
        // it. Without one (an iPad), the two columns share the width.
        let gap = fold.map { max($0.width, 24) } ?? 48
        let left = fold.map { max($0.midX - gap / 2, 0) }
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: 0) {
                header(sky.ramadan)
                    .padding(.horizontal, 28)

                // A fixed size: the column is short, and a smaller dial cuts the countdown.
                hero(sky.ramadan)
                    .frame(width: 260, height: 260)
                    .padding(.horizontal, 48)
                    .background {
                        SkyArcView(date: sky.now,
                                   todayPrayerTimes: sky.day,
                                   activePrayer: effectivePrayer,
                                   animateIn: true,
                                   orbit: true)
                            .padding(.horizontal, 48)
                    }
                    .padding(.top, 24)
                    .layoutPriority(1)
                    .zIndex(1)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(minWidth: left, maxWidth: left ?? .infinity, maxHeight: .infinity)

            ScrollView {
                if let ramadan = sky.ramadan {
                    RamadanCard(status: ramadan, clockOffset: previewClock.offset)
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                }
                PrayerTimeline(day: sky.day,
                               settings: countdownManager.currentState?.azanSettings,
                               activePrayer: effectivePrayer,
                               isIqamaPhase: effectiveIsIqama,
                               now: sky.now)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaBar(edge: .bottom) { dock }
            .background(sky.ground.opacity(0.88), in: .rect(cornerRadius: 32))
            .padding(.vertical, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // SkyScene draws the sky down to 72 % of the screen. The skyline stands on that
            // line under the left column, and the ground fills the screen below it.
            GeometryReader { geo in
                let line = geo.size.height * 0.72
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: line)
                        sky.ground
                    }
                    HorizonView(date: sky.now, sunrise: sky.sunrise, sunset: sky.sunset, asr: sky.asr,
                                lightX: sky.lightX)
                        .frame(width: geo.size.width / 2)
                        .frame(maxHeight: line * 0.3, alignment: .bottom)
                        .frame(width: geo.size.width / 2, height: line + 8, alignment: .bottom)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// The tabletop pose of iPhone Duo. The top half stands up and shows the sky with the
    /// countdown. The flat half shows the sea with the times of the day. The fold is the horizon.
    private func tabletopLayout(_ sky: SkyState, horizon: CGRect, safeTop: CGFloat) -> some View {
        let latitude = AppSettings.selectedLatitude ?? AppSettings.selectedEmirate.latitude
        return ZStack(alignment: .top) {
            SeaHorizonView(date: sky.now, day: sky.day, latitude: latitude, foldY: horizon.midY + safeTop)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack {
                    if let snapshot = countdownManager.currentState {
                        TabletopCountdown(snapshot: snapshot, ramadan: sky.ramadan, live: windowActive)
                            .padding(.horizontal, 24)
                            .padding(.top, 26)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: horizon.minY)
                .overlay(alignment: .topTrailing) {
                    if let ramadan = sky.ramadan {
                        RamadanLantern(lit: ramadan.phase != .fasting, cord: 34)
                            .padding(.trailing, 40)
                            .offset(y: -safeTop)
                    }
                }

                Color.clear.frame(height: horizon.height)

                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    if let ramadan = sky.ramadan {
                        RamadanCard(status: ramadan, clockOffset: previewClock.offset)
                    }
                    TabletopChips(day: sky.day,
                                  settings: countdownManager.currentState?.azanSettings,
                                  activePrayer: effectivePrayer,
                                  sunriseActive: countdownManager.currentState?.sunrise != nil,
                                  ramadan: sky.ramadan != nil)
                    dock
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// The fold of iPhone Duo in the coordinates of `geo`, or nil on a screen without a fold.
    private static func fold(in geo: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return geo.reservedRegions(kind: .division).first(where: \.isActive)?.frame
        }
        return nil
    }

    /// The horizon for the tabletop pose: the fold, when it goes across the screen and the hinge
    /// is half open. A DEBUG launch argument, `-tabletopPreview YES`, puts it at the middle.
    private func tabletopHorizon(_ fold: CGRect?, _ geo: GeometryProxy) -> CGRect? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "tabletopPreview") {
            return CGRect(x: 0, y: geo.size.height / 2, width: geo.size.width, height: 0)
        }
        #endif
        guard hingePartiallyOpen, let fold, fold.width > fold.height else { return nil }
        return fold
    }
    #endif

    private var phaseKey: String {
        guard let phase = countdownManager.currentState?.phase else { return "" }
        return "\(phase.prayer.rawValue)|\(phase.isIqamaPhase)"
    }

    // MARK: - Header

    private func header(_ ramadan: RamadanStatus?) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(previewClock.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                if let day = countdownManager.currentState?.todayPrayerTimes {
                    Text("\(day.hijryDay) \(day.hijriMonthName) \(String(day.hijryYear))")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.opacity)
                } else {
                    Text("Iqama")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            // The lantern hangs from the top of the screen. It lights from Maghrib to Imsak.
            if let ramadan {
                RamadanLantern(lit: ramadan.phase != .fasting, cord: 34)
                    .offset(y: -40)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(_ ramadan: RamadanStatus?) -> some View {
        if let snapshot = countdownManager.currentState {
            CountdownDial(
                prayer: snapshot.phase.prayer,
                title: snapshot.phase.prayer == .zuhr && snapshot.todayPrayerTimes?.isFriday == true
                    ? "Jumu'ah" : snapshot.phase.prayer.displayName,
                isIqama: snapshot.phase.isIqamaPhase,
                // Live seconds only while the window is being looked at; a backgrounded
                // window shows a static minute-resolution value so the per-second string
                // churn (and its display-list interpolation) stops entirely.
                countdown: windowActive ? snapshot.formattedTimeRemaining : snapshot.shortFormattedTime,
                remaining: snapshot.displayRemaining,
                live: windowActive,
                isSunrise: snapshot.sunrise != nil,
                ramadan: ramadanLabel(snapshot, ramadan)
            )
            .overlay {
                StarBurst(trigger: burst,
                          color: snapshot.phase.isIqamaPhase ? Theme.accentGold : Theme.accentEmerald)
                    .padding(-60)
            }
        } else if countdownManager.error != nil {
            errorBody
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
                .padding(.vertical, 40)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .frame(height: 280)
        }
    }

    /// Keeps the current prayer's row in view above the dock. Fajr and Zuhr sit near the top of
    /// the list, so the sky stays in full view; for later prayers the list moves to its end.
    /// (A scroll to the row's id does not work here: the rows are in a nested stack, and
    /// `scrollTargetLayout` only works on the outermost one.)
    private func scrollToActive(_ prayer: Prayer?) {
        guard let prayer else { return }
        let edge: Edge = showTimePreview || prayer == .fajr || prayer == .zuhr ? .top : .bottom
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(duration: 0.8, bounce: 0.1)) {
                scrollPosition.scrollTo(edge: edge)
            }
        }
    }

    /// In Ramadan the azan for Maghrib is the Iftar, and the azan for Fajr is Imsak, the end of
    /// the Suhoor.
    private func ramadanLabel(_ snapshot: CountdownSnapshot, _ ramadan: RamadanStatus?) -> CountdownDial.RamadanLabel? {
        guard ramadan != nil, snapshot.sunrise == nil, !snapshot.phase.isIqamaPhase else { return nil }
        switch snapshot.phase.prayer {
        case .maghrib:
            return .init(phase: "Iftar in", title: "Iftar", arabic: "الإفطار")
        case .fajr:
            return .init(phase: "Suhoor ends in", title: "Imsak", arabic: "الإمساك")
        default:
            return nil
        }
    }

    private var effectivePrayer: Prayer? { countdownManager.currentState?.phase.prayer }
    private var effectiveIsIqama: Bool { countdownManager.currentState?.phase.isIqamaPhase ?? false }

    private var errorBody: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accentGold)
                .symbolEffect(.wiggle, options: .nonRepeating)
            Text("Unable to load prayer times")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button("Retry") { countdownManager.refresh() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentEmerald)
        }
    }

    // MARK: - Control dock

    /// The only glass on the screen: floating controls above the content. The live check-in
    /// prompt morphs out of the same container when an answer is pending.
    private var dock: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                if showTimePreview {
                    TimePreviewPanel { showTimePreview = false }
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        .glassEffectID("preview", in: dockNamespace)
                } else if let pending = checkIn.pendingCheckIn {
                    checkInPrompt(pending)
                }

                if adhan.playing != nil {
                    Button { adhan.stop() } label: {
                        Label("Stop Adhan", systemImage: "speaker.slash.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.accentGold)
                    .glassEffectID("adhan", in: dockNamespace)
                }

                HStack(spacing: 10) {
                    Button(action: openLocationSettings) {
                        Label(locationText, systemImage: "location.fill")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("location", in: dockNamespace)

                    Spacer(minLength: 0)

                    // TestFlight and Debug builds only. Gold while a preview runs, so a shifted
                    // clock is never mistaken for the real time.
                    if previewClock.isAvailable {
                        Button { showTimePreview.toggle() } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .tint(previewClock.isActive ? Theme.accentGold : nil)
                        .accessibilityLabel("Time preview")
                        .glassEffectID("previewButton", in: dockNamespace)
                    }

                    Button { showCheckInSetup = true } label: {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Prayer Check-in")
                    .help(checkInStatusText)
                    .glassEffectID("checkin", in: dockNamespace)

                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Settings")
                    .glassEffectID("settings", in: dockNamespace)
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: checkIn.pendingCheckIn)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: showTimePreview)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: adhan.playing)
    }

    /// Live, unanswered check-in: the in-app twin of the notification, with the answers
    /// inline (banners vanish in seconds unless the user switched the style to Alerts).
    private func checkInPrompt(_ pending: NotificationManager.CheckInState) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: pending.awaitingConfirmation ? "questionmark.circle.fill" : "figure.walk.motion")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentGold)
                    .symbolEffect(.bounce, options: .repeat(2), value: pending)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pending.awaitingConfirmation
                         ? "Did you pray \(pending.prayer.displayName)?"
                         : "\(pending.prayer.displayName) iqama is coming up")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Button("Remind me later") { checkIn.snoozeCheckIn() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("prompt", in: dockNamespace)

            Button(pending.awaitingConfirmation ? "Yes, Wallah" : "Going now") {
                checkIn.confirmPrayed()
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accentGold)
            // Dark text: white on the light gold tint is too faint to read.
            .foregroundStyle(Color(red: 0.16, green: 0.11, blue: 0.02))
            .font(.system(size: 13, weight: .semibold))
            .glassEffectID("confirm", in: dockNamespace)
        }
    }

    private func openSettings() {
        #if os(macOS)
        openSettingsAction()
        #else
        showSettings = true
        #endif
    }

    private func openLocationSettings() {
        openSettings()
    }

    private var checkInStatusText: String {
        if !checkInOnboarded { return "Set up “Did you pray?” follow-ups" }
        let enabled = [(nagFajr, "Fajr"), (nagZuhr, "Dhuhr"), (nagAsr, "Asr"),
                       (nagMaghrib, "Maghrib"), (nagIsha, "Isha")]
            .filter(\.0).map(\.1)
        if enabled.isEmpty || !notificationsEnabled { return "Off" }
        return enabled.joined(separator: ", ") + " · every \(nagInterval) min"
    }

    private var locationText: String {
        if let t = countdownManager.currentState?.todayPrayerTimes {
            return t.areaNameEn == t.emirateNameEn ? t.areaNameEn : "\(t.areaNameEn), \(t.emirateNameEn)"
        }
        return "Locating…"
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
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentGold)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Content, not a control: a material card, so the button is the only glass here.
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
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

#if os(iOS)
/// Reports whether the hinge of iPhone Duo is half open. The handler also runs when the view
/// enters a window, so the first state arrives without a change of the hinge.
private struct HingeObserver: ViewModifier {
    @Binding var partiallyOpen: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                partiallyOpen = new.hinge?.status == .partiallyOpen
            }
        } else {
            content
        }
    }
}
#endif
