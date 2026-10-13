import SwiftUI

/// Curated country list for manual selection outside the UAE. Names are localized from the ISO
/// code at runtime, then sorted, so we don't hand-maintain display strings.
enum Countries {
    static let isoCodes = [
        "SA", "EG", "US", "GB", "CA", "AU", "DE", "FR", "IN", "PK", "BD", "ID", "MY",
        "TR", "QA", "KW", "BH", "OM", "JO", "LB", "IQ", "SY", "MA", "TN", "DZ", "LY",
        "SD", "NG", "ZA", "SG", "ES", "IT", "NL", "SE", "CH", "BE", "RU", "CN", "JP",
        "KR", "PH", "TH", "BR", "NZ", "IE",
    ]

    static let list: [(iso: String, name: String)] = isoCodes
        .map { (iso: $0, name: Locale.current.localizedString(forRegionCode: $0) ?? $0) }
        .sorted { $0.name < $1.name }
}

struct SettingsView: View {
    private let store = AppSettings.shared

    // Location
    @AppStorage(AppSettings.Keys.locationMode, store: AppSettings.shared)
    private var locationMode = AppSettings.Defaults.locationMode
    @AppStorage(AppSettings.Keys.resolvedIsUAE, store: AppSettings.shared)
    private var isUAE = true
    @AppStorage(AppSettings.Keys.selectedEmirate, store: AppSettings.shared)
    private var emirateSlug = AppSettings.Defaults.selectedEmirate
    @AppStorage(AppSettings.Keys.selectedCountryISO, store: AppSettings.shared)
    private var countryISO = "GB"
    @AppStorage(AppSettings.Keys.selectedCity, store: AppSettings.shared)
    private var city = ""

    // Ramadan mode
    @AppStorage(AppSettings.Keys.ramadanMode, store: AppSettings.shared)
    private var ramadanMode = AppSettings.Defaults.ramadanMode

    // Calculation method
    @AppStorage(AppSettings.Keys.calcMethod, store: AppSettings.shared)
    private var calcMethod = AppSettings.Defaults.calcMethod

    // Iqama overrides
    @AppStorage(AppSettings.Keys.customIqamaEnabled, store: AppSettings.shared)
    private var customIqama = AppSettings.Defaults.customIqamaEnabled
    @AppStorage(AppSettings.Keys.iqamaFajr, store: AppSettings.shared) private var iqamaFajr = AppSettings.Defaults.iqamaFajr
    @AppStorage(AppSettings.Keys.iqamaZuhr, store: AppSettings.shared) private var iqamaZuhr = AppSettings.Defaults.iqamaZuhr
    @AppStorage(AppSettings.Keys.iqamaAsr, store: AppSettings.shared) private var iqamaAsr = AppSettings.Defaults.iqamaAsr
    @AppStorage(AppSettings.Keys.iqamaMaghrib, store: AppSettings.shared) private var iqamaMaghrib = AppSettings.Defaults.iqamaMaghrib
    @AppStorage(AppSettings.Keys.iqamaIsha, store: AppSettings.shared) private var iqamaIsha = AppSettings.Defaults.iqamaIsha
    @AppStorage(AppSettings.Keys.iqamaFriday, store: AppSettings.shared) private var iqamaFriday = AppSettings.Defaults.iqamaFriday

    // Notifications (main-app standard defaults)
    @AppStorage(AppSettings.Keys.notificationsEnabled)
    private var notificationsEnabled = AppSettings.Defaults.notificationsEnabled
    @AppStorage(AppSettings.Keys.notificationLeadMinutes)
    private var leadMinutes = AppSettings.Defaults.notificationLeadMinutes

    // Prayer check-in (nagging)
    @AppStorage(AppSettings.Keys.nagFajr) private var nagFajr = AppSettings.Defaults.nagFajr
    @AppStorage(AppSettings.Keys.nagZuhr) private var nagZuhr = AppSettings.Defaults.nagZuhr
    @AppStorage(AppSettings.Keys.nagAsr) private var nagAsr = AppSettings.Defaults.nagAsr
    @AppStorage(AppSettings.Keys.nagMaghrib) private var nagMaghrib = AppSettings.Defaults.nagMaghrib
    @AppStorage(AppSettings.Keys.nagIsha) private var nagIsha = AppSettings.Defaults.nagIsha
    @AppStorage(AppSettings.Keys.nagIntervalMinutes) private var nagInterval = AppSettings.Defaults.nagIntervalMinutes

    // Adhan at the azan time (main-app standard defaults)
    @AppStorage(AppSettings.Keys.adhanSound) private var adhanSound = AppSettings.Defaults.adhanSound
    @AppStorage(AppSettings.Keys.adhanFajr) private var adhanFajr = AppSettings.Defaults.adhanPrayer
    @AppStorage(AppSettings.Keys.adhanZuhr) private var adhanZuhr = AppSettings.Defaults.adhanPrayer
    @AppStorage(AppSettings.Keys.adhanAsr) private var adhanAsr = AppSettings.Defaults.adhanPrayer
    @AppStorage(AppSettings.Keys.adhanMaghrib) private var adhanMaghrib = AppSettings.Defaults.adhanPrayer
    @AppStorage(AppSettings.Keys.adhanIsha) private var adhanIsha = AppSettings.Defaults.adhanPrayer

    @ObservedObject private var location = LocationManager.shared
    @ObservedObject private var adhanPlayer = AdhanPlayer.shared

    private var isManual: Bool { locationMode == AppSettings.LocationMode.manual.rawValue }

    var body: some View {
        Form {
            locationSection
            if !isUAE { methodSection }
            iqamaSection
            adhanSection
            ramadanSection
            notificationsSection
            nagSection
            Section {
                Text(isUAE
                     ? "Prayer times for the UAE come from Awqaf (official static data)."
                     : "Prayer times outside the UAE come from the Aladhan API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        // Flexible height: a fixed frame taller than the (persisted) window clips the bottom
        // sections with no way to scroll. This keeps the form scrollable + the window resizable.
        .frame(width: 500)
        .frame(minHeight: 420, idealHeight: 620, maxHeight: .infinity)
        #endif
        .navigationTitle("Iqama")
        // A preview must not continue after the user leaves Settings.
        .onDisappear { if adhanPlayer.playing != nil { adhanPlayer.stop() } }
    }

    // MARK: - Sections

    private var locationSection: some View {
        Section("Location") {
            Picker("Source", selection: $locationMode) {
                Text("Automatic").tag(AppSettings.LocationMode.auto.rawValue)
                Text("Choose manually").tag(AppSettings.LocationMode.manual.rawValue)
            }
            .onChange(of: locationMode) { _, newValue in
                if newValue == AppSettings.LocationMode.auto.rawValue {
                    LocationManager.shared.resolveIfAuto()
                } else {
                    applyLocationChange()
                }
            }

            if isManual {
                Picker("Region", selection: $isUAE) {
                    Text("United Arab Emirates").tag(true)
                    Text("Another country").tag(false)
                }
                .onChange(of: isUAE) { _, _ in applyLocationChange() }

                if isUAE {
                    Picker("Emirate", selection: $emirateSlug) {
                        ForEach(Emirate.allCases) { e in Text(e.nameEn).tag(e.slug) }
                    }
                    .onChange(of: emirateSlug) { _, _ in applyLocationChange() }
                } else {
                    Picker("Country", selection: $countryISO) {
                        ForEach(Countries.list, id: \.iso) { c in Text(c.name).tag(c.iso) }
                    }
                    .onChange(of: countryISO) { _, _ in applyLocationChange() }
                    TextField("City", text: $city)
                        .onSubmit { applyLocationChange() }
                }
            } else {
                LabeledContent("Detected", value: location.statusMessage ?? (location.isResolving ? "Resolving…" : "—"))
                Button("Refresh location") { LocationManager.shared.beginResolve() }
            }
        }
    }

    private var methodSection: some View {
        Section("Calculation method") {
            Picker("Method", selection: $calcMethod) {
                ForEach(CalculationMethod.options, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .onChange(of: calcMethod) { _, _ in applyLocationChange() }
        }
    }

    private var iqamaSection: some View {
        Section("Iqama times") {
            Toggle("Use my own iqama offsets", isOn: $customIqama)
                .onChange(of: customIqama) { _, _ in applyLocationChange() }
            if customIqama {
                iqamaStepper("Fajr", $iqamaFajr)
                iqamaStepper("Dhuhr", $iqamaZuhr)
                iqamaStepper("Asr", $iqamaAsr)
                iqamaStepper("Maghrib", $iqamaMaghrib)
                iqamaStepper("Isha", $iqamaIsha)
                iqamaStepper("Friday", $iqamaFriday)
            } else {
                Text("Using the official Awqaf offsets where available, otherwise UAE defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iqamaStepper(_ title: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...45) {
            HStack {
                Text(title)
                Spacer()
                Text("+\(value.wrappedValue) min").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .onChange(of: value.wrappedValue) { _, _ in applyLocationChange() }
    }

    private var adhanSection: some View {
        Section {
            Picker("Voice", selection: $adhanSound) {
                ForEach(AdhanSound.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .onChange(of: adhanSound) { _, value in
                // Play the new choice, so the user hears it at once.
                if let sound = AdhanSound(rawValue: value) { adhanPlayer.play(sound) }
            }
            Button {
                if adhanPlayer.playing != nil {
                    adhanPlayer.stop()
                } else if let sound = AdhanSound(rawValue: adhanSound) {
                    adhanPlayer.play(sound)
                }
            } label: {
                Label(adhanPlayer.playing != nil ? "Stop" : "Play",
                      systemImage: adhanPlayer.playing != nil ? "stop.fill" : "play.fill")
            }

            Toggle("Fajr", isOn: $adhanFajr)
            Toggle("Dhuhr", isOn: $adhanZuhr)
            Toggle("Asr", isOn: $adhanAsr)
            Toggle("Maghrib", isOn: $adhanMaghrib)
            Toggle("Isha", isOn: $adhanIsha)

            DisclosureGroup("Recordings") {
                ForEach(AdhanSound.allCases) { sound in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sound.displayName).font(.subheadline.weight(.medium))
                        Text(sound.credit.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Source", destination: sound.credit.source)
                            .font(.caption)
                    }
                }
                Text("The app trims, fades, and normalizes the recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Adhan")
        } footer: {
            #if os(iOS)
            Text("The Adhan plays with the azan notification of each prayer that is on, when the app is closed or in the background. iOS plays the first 30 seconds or less. When the app is open, the notification has no sound.")
            #else
            Text("The full Adhan plays at the azan time of each prayer that is on, while Iqama runs in the menu bar.")
            #endif
        }
    }

    private var ramadanSection: some View {
        Section {
            Toggle("Fasting mode", isOn: Binding(
                get: { ramadanMode == AppSettings.RamadanMode.always.rawValue },
                set: { ramadanMode = ($0 ? AppSettings.RamadanMode.always : .auto).rawValue }))
        } header: {
            Text("Ramadan")
        } footer: {
            Text("In Ramadan the app shows the fasting times by itself: the Suhoor time until Imsak, the fasting bar and the Iftar countdown, and the Iftar dua at Maghrib. On other days, turn on fasting mode for a voluntary fast.")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Iqama reminders", isOn: $notificationsEnabled)
            Picker("Remind me", selection: $leadMinutes) {
                ForEach(AppSettings.leadMinuteChoices, id: \.self) { m in
                    Text("\(m) minutes before").tag(m)
                }
            }
            .disabled(!notificationsEnabled)
        }
    }

    private var nagSection: some View {
        Section("Prayer check-in") {
            Text("After iqama, keep asking “Did you pray?” until you confirm — stops when the next prayer comes in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Fajr", isOn: $nagFajr)
            Toggle("Dhuhr", isOn: $nagZuhr)
            Toggle("Asr", isOn: $nagAsr)
            Toggle("Maghrib", isOn: $nagMaghrib)
            Toggle("Isha", isOn: $nagIsha)
            Picker("Ask every", selection: $nagInterval) {
                ForEach(AppSettings.nagIntervalChoices, id: \.self) { m in
                    Text("\(m) minutes").tag(m)
                }
            }
        }
        .disabled(!notificationsEnabled)
    }

    // MARK: - Apply

    /// Re-resolve the active provider and refresh the countdown + widget after a manual change.
    private func applyLocationChange() {
        LocationManager.shared.applyChange()
    }
}
