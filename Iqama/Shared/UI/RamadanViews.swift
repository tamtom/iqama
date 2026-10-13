import SwiftUI

/// A Ramadan lantern on a cord. It lights from Maghrib to Imsak.
struct RamadanLantern: View {
    var lit: Bool
    var cord: CGFloat = 26

    private let frame = Color(red: 0.84, green: 0.69, blue: 0.40)
    private let dark = Color(red: 0.72, green: 0.57, blue: 0.25)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(frame.opacity(0.75))
                .frame(width: 1.5, height: cord)
            Canvas { ctx, size in
                // The drawing uses a 60 × 120 grid, scaled to the frame.
                let s = size.width / 60
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                func poly(_ pts: [CGPoint]) -> Path {
                    var path = Path()
                    path.addLines(pts)
                    path.closeSubpath()
                    return path
                }
                ctx.fill(poly([p(30, 0), p(22, 12), p(38, 12)]), with: .color(frame))
                ctx.fill(poly([p(16, 14), p(44, 14), p(48, 30), p(12, 30)]), with: .color(dark))
                let glass = poly([p(12, 30), p(48, 30), p(44, 92), p(16, 92)])
                ctx.fill(glass, with: .color(lit ? Color(red: 1.0, green: 0.78, blue: 0.44)
                                                 : Color(red: 1.0, green: 0.93, blue: 0.75).opacity(0.22)))
                ctx.stroke(glass, with: .color(frame), lineWidth: 2 * s)
                var ribs = Path()
                ribs.move(to: p(30, 30)); ribs.addLine(to: p(30, 92))
                ribs.move(to: p(21, 30)); ribs.addLine(to: p(23, 92))
                ribs.move(to: p(39, 30)); ribs.addLine(to: p(37, 92))
                ctx.stroke(ribs, with: .color(frame), lineWidth: s)
                ctx.fill(poly([p(14, 92), p(46, 92), p(40, 104), p(20, 104)]), with: .color(dark))
            }
            .frame(width: 34, height: 60)
            .background {
                if lit {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.77, blue: 0.43).opacity(0.7), .clear],
                                             center: .center, startRadius: 0, endRadius: 46))
                        .frame(width: 92, height: 92)
                        .offset(y: 4)
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: lit)
        .accessibilityHidden(true)
    }
}

/// The Ramadan line under the countdown: the fasting bar and the Iftar time in the day,
/// the Suhoor time at night, and the Iftar dua at Maghrib.
struct RamadanCard: View {
    var status: RamadanStatus
    /// The offset of the preview clock. The live timer runs on the real clock.
    var clockOffset: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status.phase {
            case .fasting:
                HStack(alignment: .firstTextBaseline) {
                    Text("Fasting · \(Int(status.fastProgress * 100))%")
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Text("Iftar in")
                        timer(to: status.iftar)
                    }
                    .foregroundStyle(Theme.accentGold)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                ProgressView(value: status.fastProgress)
                    .tint(Theme.accentGold)
                HStack {
                    Text("Imsak \(status.imsak, format: .dateTime.hour().minute())")
                    Spacer()
                    Text("Iftar \(status.iftar, format: .dateTime.hour().minute())")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            case .suhoor, .night:
                HStack(alignment: .firstTextBaseline) {
                    Text(status.phase == .night ? "Suhoor" : "Suhoor ends in")
                    if status.phase == .suhoor { timer(to: status.nextImsak) }
                    Spacer(minLength: 8)
                    Text("Imsak \(status.nextImsak, format: .dateTime.hour().minute())")
                        .foregroundStyle(Theme.accentGold)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            case .iftar:
                Text(RamadanStatus.iftarDua)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.accentGold)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Text("Iftar · Taqabbal Allah")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 340)
        // Content, not a control: a quiet fill, so the dock stays the only glass.
        .background(Color(red: 0.03, green: 0.05, blue: 0.11).opacity(0.42), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accentGold.opacity(0.28)))
        .accessibilityElement(children: .combine)
    }

    private func timer(to date: Date) -> some View {
        let end = date.addingTimeInterval(-clockOffset)
        return Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
            .monospacedDigit()
    }
}
