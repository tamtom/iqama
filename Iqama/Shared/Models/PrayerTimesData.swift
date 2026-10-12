import Foundation

struct PrayerTimesMonthData: Codable {
    let downloadLink: String
    let azanSettings: AzanSettings
    let prayerData: [DailyPrayerTimes]
}

struct AzanSettings: Codable {
    let fajrIqama: Int
    let fajrPrayDuration: Int
    let zuhrIqama: Int
    let zuhrPrayDurarion: Int  // Note: typo preserved from JSON
    let asrIqama: Int
    let asrPrayDuration: Int
    let magribIqama: Int       // Note: JSON uses "magrib" not "maghrib"
    let magribPrayDuration: Int
    let ishaIqama: Int
    let ishaPrayDuration: Int
    let fridayIqama: Int
    let fridayPrayDuration: Int

    func iqamaMinutes(for prayer: Prayer, isFriday: Bool) -> Int {
        if prayer == .zuhr && isFriday {
            return fridayIqama
        }
        switch prayer {
        case .fajr: return fajrIqama
        case .zuhr: return zuhrIqama
        case .asr: return asrIqama
        case .maghrib: return magribIqama
        case .isha: return ishaIqama
        }
    }
}

struct DailyPrayerTimes: Codable {
    let pid: Int
    let gDate: String
    let dayofWeek: String
    let hijryDay: Int
    let hijryMonth: Int
    let hijryYear: Int
    let emsak: String
    let fajr: String
    let shurooq: String
    let zuhr: String
    let asr: String
    let maghrib: String
    let isha: String
    let comments: String
    let areaNameAr: String
    let areaNameEn: String
    let emirateNameAr: String
    let emirateNameEn: String
    let areaID: Int
    let emirateID: Int
    let hijryMonthNameEn: String
    let hijryMonthNameAr: String
    let gMonthNameEn: String
    let gMonthNameAr: String

    /// IANA timezone the wall-clock strings should be parsed in. Absent in the bundled UAE
    /// JSON (→ parsed in the device's current timezone, correct for users inside the UAE);
    /// injected by `AladhanProvider` for non-UAE data so a manually-selected remote city still
    /// yields correct absolute instants. Optional + defaulted, so it round-trips Codable without
    /// breaking the bundled files (which never carry this key).
    var sourceTimeZoneID: String? = nil

    // Time strings are "yyyy-MM-dd'T'HH:mm:ss" local wall-clock. We cache one formatter per
    // timezone id; parsing is read-only after configuration, guarded by a lock for the widget's
    // background timeline thread.
    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(forTimeZoneID id: String?) -> DateFormatter {
        let key = id ?? "__current__"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let f = formatters[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = id.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        formatters[key] = f
        return f
    }

    private var dateFormatter: DateFormatter {
        Self.formatter(forTimeZoneID: sourceTimeZoneID)
    }

    var gregorianDate: Date? {
        dateFormatter.date(from: gDate)
    }

    func prayerTime(for prayer: Prayer) -> Date? {
        let timeString: String
        switch prayer {
        case .fajr: timeString = fajr
        case .zuhr: timeString = zuhr
        case .asr: timeString = asr
        case .maghrib: timeString = maghrib
        case .isha: timeString = isha
        }
        return dateFormatter.date(from: timeString)
    }

    /// Shurooq: the real sunrise, which anchors the daylight sky.
    var sunriseTime: Date? {
        dateFormatter.date(from: shurooq)
    }

    var isFriday: Bool {
        dayofWeek == "Friday"
    }

    var hijriDateString: String {
        "\(hijryDay) \(hijriMonthName) \(hijryYear)"
    }

    /// Readable transliteration; the Awqaf feed spells months as "JamadAlAwal".
    var hijriMonthName: String {
        let names = ["Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Ula",
                     "Jumada al-Akhirah", "Rajab", "Sha'ban", "Ramadan", "Shawwal",
                     "Dhu al-Qi'dah", "Dhu al-Hijjah"]
        return (1...12).contains(hijryMonth) ? names[hijryMonth - 1] : hijryMonthNameEn
    }

    /// Fraction of the lunar cycle (0 = new moon, 0.5 = full), from the Hijri day.
    var moonPhase: Double {
        (Double(max(1, hijryDay)) - 0.5) / 29.53
    }
}
