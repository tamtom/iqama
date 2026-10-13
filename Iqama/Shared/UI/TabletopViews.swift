#if os(iOS)
import SwiftUI

/// The countdown in the sky half of the tabletop pose. It is large and has no dial, because
/// the sun itself crosses the sky behind it.
struct TabletopCountdown: View {
    var snapshot: CountdownSnapshot
    var ramadan: RamadanStatus?
    var live: Bool

    private static let coral = Color(red: 1.0, green: 0.62, blue: 0.42)

    var body: some View {
        let text = labels
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(text.dot).frame(width: 7, height: 7)
                Text(text.phase)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(.white.opacity(0.94))

            Text(live ? snapshot.formattedTimeRemaining : snapshot.shortFormattedTime)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText(countsDown: true))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(text.arabic)
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.88))
            }

            if ramadan?.phase == .iftar {
                Text(RamadanStatus.iftarDua)
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.accentGold)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.45), radius: 14, y: 1)
        .accessibilityElement(children: .combine)
    }

    private var labels: (phase: String, title: String, arabic: String, dot: Color) {
        let prayer = snapshot.phase.prayer
        let isFriday = snapshot.todayPrayerTimes?.isFriday == true
        let title = prayer == .zuhr && isFriday ? "Jumu'ah" : prayer.displayName
        if snapshot.sunrise != nil {
            return ("Sunrise in", "Sunrise", "الشروق", Self.coral)
        }
        if snapshot.phase.isIqamaPhase {
            return ("Iqama in", title, prayer.arabicName, Theme.accentGold)
        }
        if ramadan != nil && prayer == .maghrib {
            return ("Iftar in", "Iftar", "الإفطار", Theme.accentGold)
        }
        if ramadan != nil && prayer == .fajr {
            return ("Suhoor ends in", "Imsak", "الإمساك", Theme.accentGold)
        }
        return ("Azan in", title, prayer.arabicName, Theme.accentEmerald)
    }
}

/// The six times of the day in one row, on the flat half of the tabletop pose.
struct TabletopChips: View {
    var day: DailyPrayerTimes?
    var settings: AzanSettings?
    var activePrayer: Prayer?
    /// True when the countdown shows the sunrise. Then the sunrise chip is the active chip.
    var sunriseActive: Bool
    var ramadan: Bool

    private static let coral = Color(red: 1.0, green: 0.62, blue: 0.42)

    private struct Chip: Identifiable {
        let id: String
        let name: String
        let time: Date?
        let sub: String
        let active: Bool
        var color: Color? = nil
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                VStack(spacing: 2) {
                    Text(chip.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(chip.color ?? (chip.active ? Theme.accentGold : .white.opacity(0.85)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Group {
                        if let time = chip.time {
                            Text(time, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        } else {
                            Text("--:--")
                        }
                    }
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(chip.sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(chip.active ? Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.62)
                                        : Color(red: 0.03, green: 0.05, blue: 0.09).opacity(0.48),
                            in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(chip.active ? Theme.accentEmerald.opacity(0.75) : .white.opacity(0.08),
                                      lineWidth: 1.5)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var chips: [Chip] {
        let isFriday = day?.isFriday == true
        func iqama(_ prayer: Prayer) -> String {
            guard let azan = day?.prayerTime(for: prayer),
                  let minutes = settings?.iqamaMinutes(for: prayer, isFriday: isFriday) else { return "" }
            let time = azan.addingTimeInterval(TimeInterval(minutes * 60))
                .formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
            return time
        }
        func chip(_ prayer: Prayer, name: String? = nil, sub: String? = nil) -> Chip {
            let title = prayer == .zuhr && isFriday ? "Jumu'ah" : prayer.displayName
            return Chip(id: prayer.rawValue, name: name ?? title, time: day?.prayerTime(for: prayer),
                        sub: sub ?? "Iqama \(iqama(prayer))",
                        active: !sunriseActive && prayer == activePrayer)
        }
        return [
            ramadan ? chip(.fajr, name: "Imsak", sub: "Fajr · iq \(iqama(.fajr))") : chip(.fajr),
            Chip(id: "sunrise", name: "Sunrise", time: day?.sunriseTime, sub: "Shurooq",
                 active: sunriseActive, color: Self.coral),
            chip(.zuhr),
            chip(.asr),
            ramadan ? chip(.maghrib, name: "Iftar", sub: "Maghrib · iq \(iqama(.maghrib))") : chip(.maghrib),
            chip(.isha),
        ]
    }
}
#endif
