import SwiftUI

/// A burst of small eight-point stars that flies out from the center when `trigger` changes
/// (azan or iqama arrives). It draws nothing between bursts, and only fades with Reduce Motion.
struct StarBurst: View {
    var trigger: Int
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    private let duration = 1.8

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation) { ctx in
                    let p = min(1, ctx.date.timeIntervalSince(start) / duration)
                    Canvas { gc, size in draw(in: &gc, size: size, progress: p) }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            start = .now
            Task {
                try? await Task.sleep(for: .seconds(duration))
                start = nil
            }
        }
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, progress p: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let eased = 1 - pow(1 - p, 3)

        // Expanding ring of light.
        let ringRadius = min(size.width, size.height) * (0.3 + 0.35 * eased)
        gc.stroke(Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                         width: ringRadius * 2, height: ringRadius * 2)),
                  with: .color(color.opacity(0.5 * (1 - p))), lineWidth: 2 + 6 * (1 - p))
        guard !reduceMotion else { return }

        for i in 0..<28 {
            let seed = Double(i) * 12.9898
            let angle = Double(i) / 28 * 2 * .pi + sin(seed) * 0.2
            let distance = min(size.width, size.height) * (0.25 + (0.3 + 0.2 * abs(sin(seed * 3))) * eased)
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            let radius = (3 + 3 * abs(cos(seed))) * (1 - 0.4 * p)
            var star = gc
            star.translateBy(x: point.x, y: point.y)
            star.rotate(by: .radians(p * 2 + seed))
            star.fill(Self.star(radius: radius), with: .color((i.isMultiple(of: 3) ? Theme.glowSoft : color).opacity(1 - p)))
        }
    }

    /// Eight-point star: two squares rotated 45° apart.
    private static func star(radius r: Double) -> Path {
        var path = Path()
        for offset in [0.0, Double.pi / 4] {
            for k in 0..<4 {
                let a = Double(k) * .pi / 2 + offset
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                k == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
        }
        return path
    }
}
