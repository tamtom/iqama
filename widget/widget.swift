//
//  widget.swift
//  widget
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct PrayerTimelineEntry: TimelineEntry {
    let date: Date
    let prayer: Prayer
    let isIqamaPhase: Bool
    let targetTime: Date              // azan or iqama, whichever comes next
    let azanTime: Date
    let iqamaTime: Date
    let hijriDate: String
    let day: DailyPrayerTimes?        // for the arc ticks and the prayer list
    let sky: SkyColors
    let bodyNormalizedX: Double       // sun/moon position along its arc [0,1]
    let bodyIsDay: Bool
    /// The sunrise, when the countdown shows it (after the Fajr iqama, before the sunrise).
    var sunrise: Date? = nil

    /// What the countdown counts to: the sunrise, or the next azan or iqama.
    var countdownTarget: Date { sunrise ?? targetTime }

    var accent: Color { sunrise != nil ? Theme.sunrise : isIqamaPhase ? Theme.accentGold : Theme.accentEmerald }

    static var placeholder: PrayerTimelineEntry {
        let now = Date()
        let target = now.addingTimeInterval(38 * 60)
        return PrayerTimelineEntry(
            date: now, prayer: .asr, isIqamaPhase: false,
            targetTime: target,
            azanTime: target,
            iqamaTime: target.addingTimeInterval(20 * 60),
            hijriDate: "1 Jumada al-Ula 1448",
            day: nil,
            sky: SkyPalette.colors(at: now, sunrise: nil, sunset: nil),
            bodyNormalizedX: 0.75,
            bodyIsDay: true
        )
    }
}

// MARK: - Timeline Provider

struct PrayerTimelineProvider: TimelineProvider {
    typealias Entry = PrayerTimelineEntry

    func placeholder(in context: Context) -> PrayerTimelineEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PrayerTimelineEntry) -> Void) {
        completion(createEntry(for: Date()) ?? .placeholder)
    }

    /// Entries every 15 minutes for 6 hours, plus one at each azan, iqama, and sunrise. The sky and the
    /// sun follow the time; the countdown text runs live between entries.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerTimelineEntry>) -> Void) {
        let now = Date()
        let horizon = now.addingTimeInterval(6 * 3600)
        var dates: Set<Date> = [now]
        for minutes in stride(from: 15, through: 360, by: 15) { dates.insert(now.addingTimeInterval(Double(minutes) * 60)) }

        var cursor = now
        for _ in 0..<12 {
            guard let entry = createEntry(for: cursor), entry.targetTime <= horizon else { break }
            dates.insert(entry.targetTime)
            if let sunrise = entry.sunrise { dates.insert(sunrise) }
            cursor = entry.targetTime.addingTimeInterval(1)
        }

        var entries = dates.sorted().compactMap(createEntry(for:))
        if entries.isEmpty { entries.append(.placeholder) }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }

    private func createEntry(for date: Date) -> PrayerTimelineEntry? {
        let service = PrayerTimesService.shared
        guard let info = try? service.getNextPrayerInfo(from: date) else { return nil }
        let (prayer, azan, iqama, day) = info
        let isIqama = date >= azan && date < iqama
        let target = isIqama ? iqama : azan

        let sunrise = day.sunriseTime ?? day.prayerTime(for: .fajr).map { $0.addingTimeInterval(80 * 60) }
        let sunset = day.prayerTime(for: .maghrib)
        let body = SkyGeometry.bodyNormalized(at: date, day: day)

        return PrayerTimelineEntry(
            date: date, prayer: prayer, isIqamaPhase: isIqama,
            targetTime: target,
            azanTime: azan, iqamaTime: iqama,
            hijriDate: day.hijriDateString,
            day: day,
            sky: SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset,
                                   asr: day.prayerTime(for: .asr)),
            bodyNormalizedX: body.x,
            bodyIsDay: body.isDay,
            sunrise: day.sunriseCountdownTarget(nextPrayer: prayer, isIqama: isIqama, now: date)
        )
    }
}

// MARK: - Widget Definition

struct PrayerWidget: Widget {
    let kind: String = "PrayerTimesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimelineProvider()) { entry in
            PrayerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Iqama")
        .description("Countdown to the next azan and iqama, under today's sky.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PrayerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PrayerTimelineEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumWidgetView(entry: entry)
            case .systemLarge:  LargeWidgetView(entry: entry)
            default:            SmallWidgetView(entry: entry)
            }
        }
        .preferredColorScheme(.dark)
        // The sky and the skyline are the background, so the clear and tinted home screen
        // modes remove them and keep the text.
        .containerBackground(for: .widget) {
            WidgetSky(entry: entry, skyline: family != .systemLarge)
        }
    }
}

// MARK: - Background

/// The app's sky for the entry's moment: zenith to horizon, the light of the sun or moon,
/// stars at night, and the skyline at the bottom.
private struct WidgetSky: View {
    let entry: PrayerTimelineEntry
    var skyline = true

    var body: some View {
        let sky = entry.sky
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Theme.blend(sky.zenith, .black, 0.12), sky.zenith,
                                    Theme.blend(sky.zenith, sky.horizon, 0.5), sky.horizon],
                           startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [sky.glow.opacity(entry.bodyIsDay ? 0.3 + 0.35 * sky.warmth : 0.16), .clear],
                           center: UnitPoint(x: 0.5 - 0.45 * cos(entry.bodyNormalizedX * .pi),
                                             y: 0.2 - 0.15 * sin(entry.bodyNormalizedX * .pi)),
                           startRadius: 2, endRadius: 240)
                .blendMode(.screen)

            if sky.light < 0.3 {
                StillStars()
                    .opacity(0.9 * (1 - sky.light / 0.3))
            }

            if skyline {
                WidgetSkyline(sky: sky, height: 46)
            }
        }
    }
}

/// The city behind the mosque, colored by the sky. Wide widgets crop the sides and keep
/// the mosque in the middle.
private struct WidgetSkyline: View {
    let sky: SkyColors
    var height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("HorizonCity")
                .resizable()
                .scaledToFill()
                .foregroundStyle(sky.cityColor)
                .frame(height: height * 0.92)
                .offset(y: -height * 0.12)
            Image("HorizonMosque")
                .resizable()
                .scaledToFill()
                .foregroundStyle(sky.groundColor)
                .frame(height: height)
        }
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// A fixed field of stars; a widget is a still image, so they don't move.
private struct StillStars: View {
    var body: some View {
        Canvas { gc, size in
            var state: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                return Double(state % 10_000) / 10_000
            }
            for _ in 0..<40 {
                let x = next() * size.width, y = next() * size.height * 0.7
                let r = 0.4 + next() * 1.0
                gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(0.35 + 0.5 * next())))
            }
        }
    }
}

// MARK: - Shared components

private struct PhaseLabel: View {
    let entry: PrayerTimelineEntry

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(entry.accent)
                .frame(width: 5, height: 5)
                .shadow(color: entry.accent.opacity(0.8), radius: 3)
            Text(entry.sunrise != nil ? "Sunrise in" : entry.isIqamaPhase ? "Iqama in" : "Azan in")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct PrayerTitle: View {
    let entry: PrayerTimelineEntry
    var size: CGFloat

    private var name: String {
        if entry.sunrise != nil { return "Sunrise" }
        return entry.prayer == .zuhr && entry.day?.isFriday == true ? "Jumu'ah" : entry.prayer.displayName
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(entry.sunrise != nil ? "الشروق" : entry.prayer.arabicName)
                .font(.system(size: size * 0.75))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Counts down live and stops at zero; the next entry takes over at the azan, the iqama, or the sunrise.
private struct Countdown: View {
    let entry: PrayerTimelineEntry
    var size: CGFloat

    var body: some View {
        Text(timerInterval: entry.date...max(entry.date, entry.countdownTarget), countsDown: true)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .shadow(color: entry.accent.opacity(0.6), radius: size * 0.3)
            .widgetAccentable()
    }
}

private struct TargetLine: View {
    let entry: PrayerTimelineEntry

    var body: some View {
        Text("\(entry.sunrise != nil ? "Sunrise" : entry.isIqamaPhase ? "Iqama" : "Azan") at \(entry.countdownTarget.formatted(date: .omitted, time: .shortened))")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

private struct PrayerList: View {
    let entry: PrayerTimelineEntry
    var rowSpacing: CGFloat = 3
    var showArabic = true
    var showIqama = false

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Prayer.orderedPrayers, id: \.self) { prayer in
                if let azan = entry.day?.prayerTime(for: prayer) {
                    row(prayer, azan: azan)
                }
            }
        }
    }

    private func row(_ prayer: Prayer, azan: Date) -> some View {
        let isCurrent = prayer == entry.prayer
        let iqamaMinutes = entry.day.flatMap { day in
            (try? PrayerTimesService.shared.getAzanSettings(for: day.gregorianDate ?? entry.date))?
                .iqamaMinutes(for: prayer, isFriday: day.isFriday)
        } ?? 0
        let passed = !isCurrent && azan.addingTimeInterval(Double(iqamaMinutes) * 60) < entry.date
        return HStack(spacing: 7) {
            Image(systemName: prayer.widgetSymbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isCurrent ? entry.accent : Theme.textMuted)
                .frame(width: 14)
            Text(prayer.displayName)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if showArabic {
                Text(prayer.arabicName)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 4)
            if showIqama {
                Text("Iqama \(azan.addingTimeInterval(Double(iqamaMinutes) * 60).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(azan, style: .time)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? entry.accent : Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isCurrent {
                Capsule()
                    .fill(Color.white.opacity(0.09))
                    .overlay(Capsule().stroke(entry.accent.opacity(0.35), lineWidth: 0.6))
            }
        }
        .opacity(passed ? 0.5 : 1)
    }
}

private extension Prayer {
    var widgetSymbol: String {
        switch self {
        case .fajr: return "sun.horizon"
        case .zuhr: return "sun.max"
        case .asr: return "sun.min"
        case .maghrib: return "sunset"
        case .isha: return "moon.stars"
        }
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: PrayerTimelineEntry
    /// The medium widget lists the times beside it, so it leaves this line out.
    var showsTarget = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center) {
                PhaseLabel(entry: entry)
                Spacer(minLength: 0)
                CelestialBodyGlyph(isDay: entry.bodyIsDay, size: 16, moonPhase: entry.day?.moonPhase ?? 0.5)
                    .frame(width: 16, height: 16)
            }
            PrayerTitle(entry: entry, size: 16)
                .padding(.top, 4)
            Countdown(entry: entry, size: 30)
            if showsTarget { TargetLine(entry: entry) }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: PrayerTimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SmallWidgetView(entry: entry, showsTarget: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            PrayerList(entry: entry, rowSpacing: 1, showArabic: false)
                .frame(width: 168)
        }
    }
}

// MARK: - Large

/// The app's main screen in small: the date, the countdown with the sun or moon on its orbit, the
/// skyline, and today's prayers on the ground below it.
struct LargeWidgetView: View {
    let entry: PrayerTimelineEntry
    /// The clear and tinted home screens render content in one tint, so the skyline and the
    /// ground would become a solid block there. Only full color shows them.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.hijriDate)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
            }

            ZStack {
                SkyArcView(date: entry.date, todayPrayerTimes: entry.day, activePrayer: entry.prayer,
                           bodySize: 20, orbit: true, orbitGap: 16, interactive: false)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.38), .clear],
                                         center: .center, startRadius: 0, endRadius: 64))
                VStack(spacing: 2) {
                    PhaseLabel(entry: entry)
                    Countdown(entry: entry, size: 26)
                    PrayerTitle(entry: entry, size: 13)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 128, height: 128)
            .padding(.top, 26)

            Spacer(minLength: 4)

            // The skyline stands on the ground, and the list sits on the ground.
            if renderingMode == .fullColor {
                VStack(spacing: 0) {
                    WidgetSkyline(sky: entry.sky, height: 40)
                    PrayerList(entry: entry, rowSpacing: 1, showIqama: true)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                        .background(entry.sky.groundColor)
                }
                .padding(.horizontal, -16)
                .padding(.bottom, -16)
            } else {
                PrayerList(entry: entry, rowSpacing: 1, showIqama: true)
            }
        }
    }
}

#Preview(as: .systemSmall) {
    PrayerWidget()
} timeline: {
    PrayerTimelineEntry.placeholder
}

#Preview(as: .systemMedium) {
    PrayerWidget()
} timeline: {
    PrayerTimelineEntry.placeholder
}

#Preview(as: .systemLarge) {
    PrayerWidget()
} timeline: {
    PrayerTimelineEntry.placeholder
}
