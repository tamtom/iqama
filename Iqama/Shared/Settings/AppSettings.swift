import Foundation

// Storage keys and defaults for user-tunable preferences.
// Views read these via @AppStorage(AppSettings.Keys.X); non-view code reads through the
// computed accessors below.
//
// `shared` is the store for location/iqama/calc keys that the widget must also see. For now
// it is `.standard`; Step 4 (App Group) repoints it at a shared suite so the sandboxed widget
// reads the same selection. Notification keys stay in `.standard` (main app only).
enum AppSettings {
    enum Keys {
        static let notificationLeadMinutes = "notificationLeadMinutes"
        static let notificationsEnabled = "notificationsEnabled"

        // Prayer check-in (nagging)
        static let nagFajr = "nagFajr"
        static let nagZuhr = "nagZuhr"
        static let nagAsr = "nagAsr"
        static let nagMaghrib = "nagMaghrib"
        static let nagIsha = "nagIsha"
        static let nagIntervalMinutes = "nagIntervalMinutes"
        static let nagResolvedWindow = "nagResolvedWindow"  // last prayer window confirmed prayed
        static let checkInOnboarded = "checkInOnboarded"    // saw the Prayer Check-in intro sheet

        // Adhan at the azan time
        static let adhanSound = "adhanSound"                // AdhanSound.rawValue
        static let adhanFajr = "adhanFajr"
        static let adhanZuhr = "adhanZuhr"
        static let adhanAsr = "adhanAsr"
        static let adhanMaghrib = "adhanMaghrib"
        static let adhanIsha = "adhanIsha"

        // Ramadan mode
        static let ramadanMode = "ramadanMode"              // RamadanMode.rawValue

        // Test tools (TestFlight, Debug, or a Mac with `showTestTools` set)
        static let showTestTools = "showTestTools"          // macOS: shows the test tools in a Release build

        // Location
        static let locationConfirmed = "locationConfirmed"  // user finished first-run setup
        static let locationMode = "locationMode"            // "auto" | "manual"
        static let selectedEmirate = "selectedEmirate"      // Emirate.slug (UAE)
        static let selectedCountryISO = "selectedCountryISO"
        static let selectedCity = "selectedCity"
        static let selectedLatitude = "selectedLatitude"
        static let selectedLongitude = "selectedLongitude"
        static let selectedTimeZone = "selectedTimeZone"    // IANA id for non-UAE parsing
        static let resolvedIsUAE = "resolvedIsUAE"

        // Non-UAE calculation method (Aladhan). -1 = auto by country.
        static let calcMethod = "calcMethod"

        // Iqama overrides
        static let customIqamaEnabled = "customIqamaEnabled"
        static let iqamaFajr = "iqamaFajr"
        static let iqamaZuhr = "iqamaZuhr"
        static let iqamaAsr = "iqamaAsr"
        static let iqamaMaghrib = "iqamaMaghrib"
        static let iqamaIsha = "iqamaIsha"
        static let iqamaFriday = "iqamaFriday"
    }

    enum Defaults {
        static let notificationLeadMinutes = 10
        static let notificationsEnabled = true

        // Nagging: only Dhuhr + Asr by default; other prayers keep the plain reminder.
        static let nagFajr = false
        static let nagZuhr = true
        static let nagAsr = true
        static let nagMaghrib = false
        static let nagIsha = false
        static let nagIntervalMinutes = 15

        static let adhanSound = "makkah"   // AdhanSound.makkah
        static let adhanPrayer = true   // the Adhan plays for every prayer until the user turns one off

        static let ramadanMode = RamadanMode.auto.rawValue

        static let locationMode = "auto"
        static let selectedEmirate = Emirate.dubai.slug
        static let calcMethod = -1   // auto by country

        static let customIqamaEnabled = false
        // Official UAE Awqaf iqama offsets (minutes after azan) — used as the defaults
        // everywhere, including non-UAE where no official iqama data exists.
        static let iqamaFajr = 25
        static let iqamaZuhr = 20
        static let iqamaAsr = 20
        static let iqamaMaghrib = 5
        static let iqamaIsha = 20
        static let iqamaFriday = 20
    }

    // Friendly choices we render in the settings pickers.
    static let leadMinuteChoices: [Int] = [2, 5, 10, 15, 20, 30]
    static let iqamaChoices: [Int] = Array(0...45)
    static let nagIntervalChoices: [Int] = [5, 10, 15, 20, 30]

    // MARK: - Stores

    /// Store shared with the widget via the App Group (falls back to standard defaults if the
    /// group container isn't available, e.g. before provisioning — main app still works).
    static var shared: UserDefaults { AppGroup.defaults ?? .standard }
    private static var notif: UserDefaults { .standard }

    // MARK: - Notifications

    static var notificationLeadMinutes: Int {
        notif.object(forKey: Keys.notificationLeadMinutes) as? Int ?? Defaults.notificationLeadMinutes
    }

    static var notificationsEnabled: Bool {
        notif.object(forKey: Keys.notificationsEnabled) as? Bool ?? Defaults.notificationsEnabled
    }

    // MARK: - Prayer check-in (nagging)

    static func nagKey(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return Keys.nagFajr
        case .zuhr: return Keys.nagZuhr
        case .asr: return Keys.nagAsr
        case .maghrib: return Keys.nagMaghrib
        case .isha: return Keys.nagIsha
        }
    }

    static func nagDefault(for prayer: Prayer) -> Bool {
        switch prayer {
        case .fajr: return Defaults.nagFajr
        case .zuhr: return Defaults.nagZuhr
        case .asr: return Defaults.nagAsr
        case .maghrib: return Defaults.nagMaghrib
        case .isha: return Defaults.nagIsha
        }
    }

    /// Whether the "did you pray?" follow-up loop is enabled for this prayer.
    static func nagEnabled(for prayer: Prayer) -> Bool {
        notif.object(forKey: nagKey(for: prayer)) as? Bool ?? nagDefault(for: prayer)
    }

    /// Minutes between "did you pray?" follow-ups (also the delay of the first one after iqama).
    static var nagIntervalMinutes: Int {
        notif.object(forKey: Keys.nagIntervalMinutes) as? Int ?? Defaults.nagIntervalMinutes
    }

    /// The last prayer window the user confirmed (survives relaunch so we don't re-nag).
    static var nagResolvedWindow: String? {
        get { notif.string(forKey: Keys.nagResolvedWindow) }
        set { notif.set(newValue, forKey: Keys.nagResolvedWindow) }
    }

    // MARK: - Adhan

    static func adhanKey(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return Keys.adhanFajr
        case .zuhr: return Keys.adhanZuhr
        case .asr: return Keys.adhanAsr
        case .maghrib: return Keys.adhanMaghrib
        case .isha: return Keys.adhanIsha
        }
    }

    /// Whether the Adhan plays (and the azan alert shows) at this prayer's azan time.
    static func adhanEnabled(for prayer: Prayer) -> Bool {
        notif.object(forKey: adhanKey(for: prayer)) as? Bool ?? Defaults.adhanPrayer
    }

    // MARK: - Ramadan

    /// `auto` turns Ramadan mode on in the month of Ramadan. `always` shows it on every day,
    /// as a preview. `off` never shows it.
    enum RamadanMode: String, CaseIterable { case auto, always, off }

    static var ramadanMode: RamadanMode {
        RamadanMode(rawValue: shared.string(forKey: Keys.ramadanMode) ?? Defaults.ramadanMode) ?? .auto
    }

    // MARK: - Location

    enum LocationMode: String { case auto, manual }

    static var locationConfirmed: Bool {
        shared.object(forKey: Keys.locationConfirmed) as? Bool ?? false
    }

    static var locationMode: LocationMode {
        LocationMode(rawValue: shared.string(forKey: Keys.locationMode) ?? Defaults.locationMode) ?? .auto
    }

    static var selectedEmirate: Emirate {
        Emirate.from(slug: shared.string(forKey: Keys.selectedEmirate)) ?? .dubai
    }

    static var selectedCountryISO: String? { shared.string(forKey: Keys.selectedCountryISO) }
    static var selectedCity: String? { shared.string(forKey: Keys.selectedCity) }
    static var selectedTimeZone: String? { shared.string(forKey: Keys.selectedTimeZone) }
    static var selectedLatitude: Double? {
        shared.object(forKey: Keys.selectedLatitude) as? Double
    }
    static var selectedLongitude: Double? {
        shared.object(forKey: Keys.selectedLongitude) as? Double
    }

    /// Whether the resolved location is inside the UAE (drives Awqaf-vs-Aladhan routing).
    /// Defaults to true so the app always has a valid UAE source on first launch.
    static var resolvedIsUAE: Bool {
        shared.object(forKey: Keys.resolvedIsUAE) as? Bool ?? true
    }

    static var calcMethod: Int {
        shared.object(forKey: Keys.calcMethod) as? Int ?? Defaults.calcMethod
    }

    // MARK: - Iqama overrides

    static var customIqamaEnabled: Bool {
        shared.object(forKey: Keys.customIqamaEnabled) as? Bool ?? Defaults.customIqamaEnabled
    }

    static func iqamaOverride(forKey key: String, default def: Int) -> Int {
        shared.object(forKey: key) as? Int ?? def
    }

    /// The user's per-prayer iqama offsets (falls back to the UAE defaults per prayer).
    static var customAzanSettings: AzanSettings {
        AzanSettings(
            fajrIqama: iqamaOverride(forKey: Keys.iqamaFajr, default: Defaults.iqamaFajr),
            fajrPrayDuration: AzanSettings.uaeDefault.fajrPrayDuration,
            zuhrIqama: iqamaOverride(forKey: Keys.iqamaZuhr, default: Defaults.iqamaZuhr),
            zuhrPrayDurarion: AzanSettings.uaeDefault.zuhrPrayDurarion,
            asrIqama: iqamaOverride(forKey: Keys.iqamaAsr, default: Defaults.iqamaAsr),
            asrPrayDuration: AzanSettings.uaeDefault.asrPrayDuration,
            magribIqama: iqamaOverride(forKey: Keys.iqamaMaghrib, default: Defaults.iqamaMaghrib),
            magribPrayDuration: AzanSettings.uaeDefault.magribPrayDuration,
            ishaIqama: iqamaOverride(forKey: Keys.iqamaIsha, default: Defaults.iqamaIsha),
            ishaPrayDuration: AzanSettings.uaeDefault.ishaPrayDuration,
            fridayIqama: iqamaOverride(forKey: Keys.iqamaFriday, default: Defaults.iqamaFriday),
            fridayPrayDuration: AzanSettings.uaeDefault.fridayPrayDuration
        )
    }
}
