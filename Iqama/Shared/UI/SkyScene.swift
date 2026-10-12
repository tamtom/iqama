import SwiftUI

/// The full-screen living sky behind the main screen: a slowly breathing mesh gradient in the
/// time-of-day palette, a halo that follows the sun or moon, drifting clouds by day, and
/// twinkling stars with the odd shooting star by night.
///
/// Motion stops when Reduce Motion is on, and on macOS when the window is inactive, so a
/// background window costs nothing.
struct SkyScene: View {
    var bodyNormalizedX: Double
    var bodyIsDay: Bool
    var sunrise: Date?
    var sunset: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    private var isInactive: Bool { controlActiveState == .inactive }
    #else
    private var isInactive: Bool { false }
    #endif

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isInactive || reduceMotion)) { ctx in
            let date = ctx.date.addingTimeInterval(PreviewClock.shared.offset)
            let t = date.timeIntervalSinceReferenceDate
            let sky = SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset)
            ZStack {
                MeshGradient(width: 3, height: 3,
                             points: meshPoints(t: reduceMotion ? 0 : t),
                             colors: meshColors(sky))

                // The sun or moon lights up the sky around it.
                RadialGradient(
                    colors: [sky.glow.opacity(bodyIsDay ? 0.25 + 0.35 * sky.light : 0.16), .clear],
                    center: .init(x: bodyNormalizedX, y: 0.14),
                    startRadius: 2,
                    endRadius: bodyIsDay ? 460 : 300
                )
                .blendMode(.screen)

                // Stars fade in as the light goes; clouds take over in daylight.
                if sky.light < 0.3 {
                    StarField(seed: 7, count: 90)
                        .opacity(0.9 * (1 - sky.light / 0.3))
                    if sky.light < 0.05 { ShootingStars(time: t) }
                }
                if sky.light > 0.25 {
                    CloudLayer(time: reduceMotion ? 0 : t, tint: Theme.blend(.white, sky.glow, 0.35))
                        .opacity(min(1, (sky.light - 0.25) / 0.4) * 0.9)
                }

                IslamicStarOverlay(tileSize: 72, strokeWidth: 0.5)
                    .opacity(0.03)
                    .blendMode(.overlay)
            }
            .allowsHitTesting(false)
        }
    }

    /// 3×3 control points; the inner points drift on slow, out-of-phase sine waves.
    private func meshPoints(t: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ amp: Double) -> Float {
            Float(sin(t * speed + phase) * amp)
        }
        return [
            [0, 0], [0.5 + wave(0.05, 0, 0.08), 0], [1, 0],
            [0, 0.42 + wave(0.04, 1, 0.06)],
            [0.5 + wave(0.06, 2, 0.10), 0.45 + wave(0.05, 3, 0.07)],
            [1, 0.42 + wave(0.045, 4, 0.06)],
            [0, 0.72], [0.5 + wave(0.035, 5, 0.10), 0.72], [1, 0.72],
        ]
    }

    /// Zenith at the top, the horizon color where the skyline stands (about 70% down).
    private func meshColors(_ sky: SkyColors) -> [Color] {
        let mid = Theme.blend(sky.zenith, sky.horizon, 0.45)
        let warmHorizon = Theme.blend(sky.horizon, sky.glow, 0.25)
        return [
            Theme.blend(sky.zenith, .black, 0.12), sky.zenith, Theme.blend(sky.zenith, .indigo, 0.08),
            Theme.blend(mid, sky.zenith, 0.25), mid, Theme.blend(mid, sky.horizon, 0.2),
            sky.horizon, warmHorizon, sky.horizon,
        ]
    }
}

/// Soft clouds made of blurred ellipses that drift across the sky over a few minutes.
private struct CloudLayer: View {
    var time: Double
    var tint: Color = .white

    var body: some View {
        Canvas { gc, size in
            gc.addFilter(.blur(radius: 26))
            let clouds: [(y: Double, w: Double, speed: Double, offset: Double, alpha: Double)] = [
                (0.10, 0.55, 3.0, 0.0, 0.16), (0.22, 0.40, 2.2, 0.45, 0.12),
                (0.06, 0.35, 1.6, 0.75, 0.10), (0.30, 0.50, 2.6, 0.25, 0.08),
            ]
            for c in clouds {
                let span = size.width * (1 + c.w)
                let x = (time * c.speed + c.offset * span).truncatingRemainder(dividingBy: span) - size.width * c.w
                let w = size.width * c.w
                let rect = CGRect(x: x, y: size.height * c.y, width: w, height: w * 0.22)
                gc.fill(Path(ellipseIn: rect), with: .color(tint.opacity(c.alpha * 2.2)))
                gc.fill(Path(ellipseIn: rect.insetBy(dx: w * 0.18, dy: -w * 0.05).offsetBy(dx: w * 0.1, dy: -w * 0.04)),
                        with: .color(tint.opacity(c.alpha * 1.8)))
            }
        }
    }
}

/// Every 14 seconds a faint meteor crosses part of the sky; its path changes each time.
private struct ShootingStars: View {
    var time: Double
    private let period = 14.0
    private let flight = 1.1

    var body: some View {
        Canvas { gc, size in
            let cycle = (time / period).rounded(.down)
            let local = time - cycle * period
            guard local < flight else { return }
            var rng = SeededRandom(seed: UInt64(cycle.magnitude) &* 2654435761)
            let start = CGPoint(x: size.width * (0.15 + 0.7 * rng.next()), y: size.height * (0.04 + 0.2 * rng.next()))
            let angle = Double.pi * (0.78 + 0.12 * rng.next())
            let length = size.width * 0.45
            let p = local / flight
            let head = CGPoint(x: start.x + cos(angle) * length * p, y: start.y + sin(angle) * length * p)
            let tailLen = length * 0.25
            let tail = CGPoint(x: head.x - cos(angle) * tailLen, y: head.y - sin(angle) * tailLen)
            let fade = sin(p * .pi)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            gc.stroke(path,
                      with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.85 * fade)]),
                                            startPoint: tail, endPoint: head),
                      style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

/// The skyline at the bottom of the hero: a hazy city behind a mosque with palms, tinted by the
/// sky. At night the city windows glow. The ground continues below as the base for the content.
struct HorizonView: View {
    var date: Date
    var sunrise: Date?
    var sunset: Date?

    var body: some View {
        let sky = SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset)
        ZStack(alignment: .bottom) {
            Image("HorizonCity")
                .resizable()
                .scaledToFit()
                .foregroundStyle(sky.cityColor)
                .overlay {
                    if sky.light < 0.3 {
                        CityLights()
                            .mask(Image("HorizonCity").resizable().scaledToFit())
                            .opacity(1 - sky.light / 0.3)
                    }
                }
                .offset(y: -18)

            Image("HorizonMosque")
                .resizable()
                .scaledToFit()
                .foregroundStyle(sky.groundColor)
        }
        .accessibilityHidden(true)
    }
}

/// Scattered warm window lights, drawn once; the city silhouette masks them.
private struct CityLights: View {
    var body: some View {
        Canvas { gc, size in
            var rng = SeededRandom(seed: 42)
            for _ in 0..<260 {
                let x = size.width * rng.next()
                let y = size.height * (0.15 + 0.85 * rng.next())
                let warm = rng.next() > 0.3
                let color = warm ? Color(red: 1, green: 0.84, blue: 0.55) : Color(red: 0.8, green: 0.9, blue: 1)
                gc.fill(Path(CGRect(x: x, y: y, width: 1.6, height: 2.2)),
                        with: .color(color.opacity(0.35 + 0.5 * rng.next())))
            }
        }
    }
}
