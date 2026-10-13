import Foundation

/// The Ramadan state at one moment. Suhoor runs until Imsak, the fast runs from Imsak to
/// Maghrib, and the Iftar dua shows for a short time after Maghrib.
///
/// Imsak is the Fajr azan: eating and drinking are permitted until the true dawn (Al-Baqarah
/// 2:187), and the Prophet ﷺ said to eat and drink until the azan of Ibn Umm Maktum. The app
/// does not use an earlier Imsak, such as the one 10 minutes before Fajr in some timetables.
struct RamadanStatus: Equatable {
    enum Phase: Equatable {
        case suhoor     // before Imsak: the Suhoor countdown
        case fasting    // Imsak to Maghrib: the fasting bar and the Iftar countdown
        case iftar      // the first minutes after Maghrib: the Iftar dua
        case night      // after the Iftar time: the Suhoor time for tomorrow
    }

    let phase: Phase
    let imsak: Date
    let iftar: Date
    /// The next Imsak. After Maghrib it is tomorrow's Imsak, which is about 24 hours later.
    let nextImsak: Date
    /// The part of the fast that is complete, from 0 to 1.
    let fastProgress: Double

    /// The time that the Ramadan line counts down to.
    var target: Date {
        switch phase {
        case .suhoor, .night: return nextImsak
        case .fasting, .iftar: return iftar
        }
    }

    /// How long the Iftar dua shows after Maghrib.
    static let duaDuration: TimeInterval = 20 * 60

    static let iftarDua = "ذهب الظمأ وابتلّت العروق وثبت الأجر إن شاء الله"

    /// The status for `now`, or nil when Ramadan mode is off for this day.
    static func at(_ now: Date, day: DailyPrayerTimes?, mode: AppSettings.RamadanMode) -> RamadanStatus? {
        guard let day, mode != .off else { return nil }
        let isRamadan = day.hijryMonth == 9
        guard isRamadan || mode == .always else { return nil }
        guard let imsak = day.prayerTime(for: .fajr),
              let iftar = day.prayerTime(for: .maghrib) else { return nil }

        let phase: Phase
        if now < imsak {
            phase = .suhoor
        } else if now < iftar {
            phase = .fasting
        } else if now < iftar.addingTimeInterval(duaDuration) {
            phase = .iftar
        } else {
            // On the last nights of the month no fast may follow, so the app does not
            // promise a Suhoor that is not there. The preview mode always shows it.
            if mode == .auto && day.hijryDay >= 29 { return nil }
            phase = .night
        }

        let nextImsak = now < imsak ? imsak : imsak.addingTimeInterval(24 * 3600)
        let span = iftar.timeIntervalSince(imsak)
        let progress = span > 0 ? min(1, max(0, now.timeIntervalSince(imsak) / span)) : 0
        return RamadanStatus(phase: phase, imsak: imsak, iftar: iftar, nextImsak: nextImsak,
                             fastProgress: phase == .suhoor ? 0 : progress)
    }
}
