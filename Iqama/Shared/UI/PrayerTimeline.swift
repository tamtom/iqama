import SwiftUI

/// Today's five prayers on the dark ground below the skyline. Passed prayers dim, and a soft
/// highlight slides to the current prayer when the phase changes.
struct PrayerTimeline: View {
    var day: DailyPrayerTimes?
    var settings: AzanSettings?
    var activePrayer: Prayer?
    var isIqamaPhase: Bool
    var now: Date

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var accent: Color { isIqamaPhase ? Theme.accentGold : Theme.accentEmerald }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(Prayer.orderedPrayers.enumerated()), id: \.element) { index, prayer in
                row(prayer)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 14)
                    .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.25 + Double(index) * 0.06),
                               value: appeared)
            }
        }
        .padding(6)
        .containerShape(.rect(cornerRadius: 24))
        .animation(.spring(duration: 0.6, bounce: 0.18), value: activePrayer)
        .onAppear { appeared = true }
    }

    private func row(_ prayer: Prayer) -> some View {
        let azan = day?.prayerTime(for: prayer)
        let minutes = settings?.iqamaMinutes(for: prayer, isFriday: day?.isFriday ?? false) ?? 0
        let iqama = azan?.addingTimeInterval(TimeInterval(minutes * 60))
        let isActive = prayer == activePrayer
        let passed = !isActive && (iqama.map { $0 < now } ?? false)
        return PrayerRow(prayer: prayer, isFriday: day?.isFriday == true, azan: azan, iqama: iqama,
                         isActive: isActive, passed: passed, accent: accent)
            .background {
                if isActive { highlightShape }
            }
    }

    private var highlightShape: some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(12)), isUniform: true)
        return shape
            .fill(Color.white.opacity(0.07))
            .overlay(shape.stroke(accent.opacity(0.35), lineWidth: 0.8))
            .matchedGeometryEffect(id: "highlight", in: highlight)
    }
}

private struct PrayerRow: View {
    var prayer: Prayer
    var isFriday: Bool
    var azan: Date?
    var iqama: Date?
    var isActive: Bool
    var passed: Bool
    var accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: prayer.symbolName)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? accent : Theme.textSecondary)
                .frame(width: 28)
                .symbolEffect(.bounce, value: isActive)

            VStack(alignment: .leading, spacing: 1) {
                Text(prayer == .zuhr && isFriday ? "Jumu'ah" : prayer.displayName)
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(prayer.arabicName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer(minLength: 8)

            if let azan, let iqama {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(azan, style: .time)
                        .font(.system(size: 15, weight: isActive ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? accent : Theme.textPrimary)
                    Text("Iqama \(iqama.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                .monospacedDigit()
            }

            Image(systemName: passed ? "checkmark" : "circle.fill")
                .font(.system(size: passed ? 11 : 6, weight: .bold))
                .foregroundStyle(passed ? Theme.textMuted : (isActive ? accent : .clear))
                .frame(width: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(passed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

extension Prayer {
    var symbolName: String {
        switch self {
        case .fajr: return "sun.horizon"
        case .zuhr: return "sun.max"
        case .asr: return "sun.min"
        case .maghrib: return "sunset"
        case .isha: return "moon.stars"
        }
    }
}
