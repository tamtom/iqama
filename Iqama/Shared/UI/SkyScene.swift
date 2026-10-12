import SwiftUI

/// The full-screen living sky behind the main screen: a slowly breathing mesh gradient in the
/// time-of-day palette, light and rays from the sun or moon, drifting clouds, golden dust and
/// birds by day, and twinkling stars with the odd shooting star by night.
///
/// Each layer redraws only as often as it moves. A `Canvas` redraws every time its parent
/// body runs, so the layers sit in separate timelines: the sky at 10 fps, the dust, birds,
/// and meteors at 24 fps and only while they can show, the stars at their own 4 fps, and the
/// ornament never. Motion stops with Reduce Motion, and on macOS when the window is inactive.
struct SkyScene: View {
    var bodyNormalizedX: Double
    var bodyIsDay: Bool
    var sunrise: Date?
    var sunset: Date?
    var asr: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    private var isInactive: Bool { controlActiveState == .inactive }
    #else
    private var isInactive: Bool { false }
    #endif

    var body: some View {
        // Once a minute: decide which layers to mount.
        TimelineView(.everyMinute) { minute in
            let sky = SkyPalette.colors(at: minute.date.addingTimeInterval(PreviewClock.shared.offset),
                                        sunrise: sunrise, sunset: sunset, asr: asr)
            GeometryReader { geo in
                let source = lightSource(in: geo.size)
                ZStack {
                    SkyLight(source: source, bodyIsDay: bodyIsDay, sunrise: sunrise, sunset: sunset, asr: asr,
                             paused: isInactive || reduceMotion)

                    // Stars fade in as the light goes.
                    if sky.light < 0.3 {
                        StarField(seed: 7, count: 90)
                            .opacity(0.9 * (1 - sky.light / 0.3))
                    }

                    if !reduceMotion && !isInactive {
                        let dust = bodyIsDay && sky.warmth > 0.25
                        let birds = bodyIsDay && sky.light > 0.5
                        let meteors = sky.light < 0.05
                        if dust || birds || meteors {
                            SkyLife(source: source, sunrise: sunrise, sunset: sunset, asr: asr,
                                    dust: dust, birds: birds, meteors: meteors)
                        }
                    }

                    IslamicStarOverlay(tileSize: 72, strokeWidth: 0.5)
                        .opacity(0.03)
                        .blendMode(.overlay)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Where the sun or moon is on screen: on the orbit around the dial, which sits about a
    /// third of the way down with a radius of about 42% of the width. The light is soft, so
    /// an approximate point is enough, also while the content scrolls.
    private func lightSource(in size: CGSize) -> CGPoint {
        let angle = min(max(bodyNormalizedX, 0), 1) * .pi
        let radius = size.width * 0.42
        return CGPoint(x: size.width / 2 - cos(angle) * radius,
                       y: size.height * 0.37 - sin(angle) * radius)
    }

}

/// The sky itself at 10 fps: the mesh, the light of the sun or moon, the rays, and the clouds.
/// Everything here moves slowly, so 10 fps looks smooth.
private struct SkyLight: View {
    var source: CGPoint
    var bodyIsDay: Bool
    var sunrise: Date?
    var sunset: Date?
    var asr: Date?
    var paused: Bool

    var body: some View {
        // Paused (Reduce Motion, or an inactive Mac window): no motion, but the colors still
        // follow the time once a minute. A paused animation schedule keeps its last date.
        if paused {
            TimelineView(.everyMinute) { ctx in sky(at: ctx.date, moving: false) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { ctx in sky(at: ctx.date, moving: true) }
        }
    }

    private func sky(at now: Date, moving: Bool) -> some View {
        let date = now.addingTimeInterval(PreviewClock.shared.offset)
        let t = moving ? date.timeIntervalSinceReferenceDate : 0
        let sky = SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset, asr: asr)
        return GeometryReader { geo in
            let unit = UnitPoint(x: source.x / max(geo.size.width, 1), y: source.y / max(geo.size.height, 1))
            ZStack {
                MeshGradient(width: 3, height: 3,
                             points: meshPoints(t: t),
                             colors: meshColors(sky, sunX: bodyIsDay ? unit.x : 0.5))

                // The sun or moon lights up the sky around it; low warm light spreads further.
                RadialGradient(
                    colors: bodyIsDay
                        ? [sky.glow.opacity(0.3 + 0.35 * sky.warmth), sky.glow.opacity(0.06 + 0.16 * sky.warmth), .clear]
                        : [sky.glow.opacity(0.16), .clear],
                    center: unit,
                    startRadius: 2,
                    endRadius: bodyIsDay ? geo.size.height * (0.5 + 0.3 * sky.warmth) : 300
                )
                .blendMode(.screen)

                if bodyIsDay && sky.light > 0.2 {
                    SunRays(time: t, origin: source, color: sky.glow)
                        .opacity(0.25 + 0.6 * sky.warmth)
                        .blendMode(.screen)
                }

                if sky.light > 0.25 {
                    CloudLayer(time: t, tint: Theme.blend(.white, sky.glow, 0.3 + 0.5 * sky.warmth))
                        .opacity(min(1, (sky.light - 0.25) / 0.4) * 0.9)
                }
            }
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

    /// Zenith at the top, the horizon color where the skyline stands (about 70% down). In warm
    /// light, the side of the sky near the sun takes its glow and the far side stays cooler.
    private func meshColors(_ sky: SkyColors, sunX: Double) -> [Color] {
        let mid = Theme.blend(sky.zenith, sky.horizon, 0.45)
        let warm = sky.warmth
        func lit(_ color: Color, _ side: Double, _ amount: Double) -> Color {
            Theme.blend(color, sky.glow, warm * amount * side)
        }
        let near = 1 - sunX, far = sunX   // weight for the left side, then the right side
        return [
            lit(Theme.blend(sky.zenith, .black, 0.12), near, 0.15), sky.zenith,
            lit(Theme.blend(sky.zenith, .indigo, 0.08), far, 0.15),
            lit(Theme.blend(mid, sky.zenith, 0.25), near, 0.45), mid,
            lit(Theme.blend(mid, sky.horizon, 0.2), far, 0.45),
            lit(sky.horizon, near, 0.35), Theme.blend(sky.horizon, sky.glow, 0.25), lit(sky.horizon, far, 0.35),
        ]
    }
}

/// The small moving things at 24 fps: golden dust in low sunlight, a passing flock of birds,
/// and the odd shooting star at night. The scene mounts this only while one of them can show.
private struct SkyLife: View {
    var source: CGPoint
    var sunrise: Date?
    var sunset: Date?
    var asr: Date?
    var dust: Bool
    var birds: Bool
    var meteors: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            let date = ctx.date.addingTimeInterval(PreviewClock.shared.offset)
            let t = date.timeIntervalSinceReferenceDate
            let sky = SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset, asr: asr)
            ZStack {
                if dust {
                    DustMotes(time: t, origin: source, color: sky.glow)
                        .opacity(min(1, (sky.warmth - 0.25) / 0.4))
                        .blendMode(.screen)
                }
                if birds {
                    Birds(time: t, color: Theme.blend(sky.zenith, .black, 0.55).opacity(0.6))
                }
                if meteors {
                    ShootingStars(time: t)
                }
            }
        }
    }
}

/// Soft rays that turn slowly around the sun. They are faint at noon and strong in the warm
/// light of Asr and sunset (the caller sets the opacity).
private struct SunRays: View {
    var time: Double
    var origin: CGPoint
    var color: Color

    var body: some View {
        Canvas { gc, size in
            let length = max(size.width, size.height) * 1.2
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: origin, startRadius: 0, endRadius: length * 0.7)
            for i in 0..<12 {
                let seed = Double(i)
                let angle = seed * 2.399 + time * 0.012 + sin(time * 0.05 + seed) * 0.06
                let spread = 0.03 + 0.03 * abs(sin(seed * 3.1))
                let alpha = 0.12 + 0.18 * (0.5 + 0.5 * sin(time * 0.25 + seed * 5))
                // Three nested wedges give the ray a soft edge without a costly blur filter.
                for layer in 1...3 {
                    let half = spread * Double(layer) / 3
                    var ray = Path()
                    ray.move(to: origin)
                    ray.addLine(to: CGPoint(x: origin.x + cos(angle - half) * length,
                                            y: origin.y + sin(angle - half) * length))
                    ray.addLine(to: CGPoint(x: origin.x + cos(angle + half) * length,
                                            y: origin.y + sin(angle + half) * length))
                    ray.closeSubpath()
                    var wedge = gc
                    wedge.opacity = alpha / 3
                    wedge.fill(ray, with: shading)
                }
            }
        }
    }
}

/// Fine dust that drifts up through the low sunlight and glints near the sun.
private struct DustMotes: View {
    var time: Double
    var origin: CGPoint
    var color: Color

    var body: some View {
        Canvas { gc, size in
            var rng = SeededRandom(seed: 99)
            for _ in 0..<50 {
                let baseX = rng.next(), baseY = rng.next()
                let speed = 0.004 + 0.008 * rng.next()
                let phase = rng.next() * 6.28
                let radius = 0.6 + 1.5 * rng.next()
                var y = (baseY - time * speed).truncatingRemainder(dividingBy: 1)
                if y < 0 { y += 1 }
                let point = CGPoint(x: (baseX + 0.02 * sin(time * 0.2 + phase)) * size.width,
                                    y: y * size.height * 0.75)
                let distance = hypot(point.x - origin.x, point.y - origin.y) / size.height
                let lit = max(0, 1 - distance * 1.4)
                let alpha = lit * (0.25 + 0.6 * (0.5 + 0.5 * sin(time * 1.3 + phase * 3)))
                guard alpha > 0.02 else { continue }
                gc.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(color.opacity(alpha)))
            }
        }
    }
}

/// Every 45 seconds a small flock flies across the day sky in a loose V; its height and
/// direction change each time.
private struct Birds: View {
    var time: Double
    var color: Color
    private let period = 45.0
    private let flight = 20.0

    var body: some View {
        Canvas { gc, size in
            let cycle = (time / period).rounded(.down)
            let local = time - cycle * period
            guard local < flight else { return }
            var rng = SeededRandom(seed: UInt64(cycle.magnitude) &* 40503 &+ 11)
            let direction: Double = rng.next() > 0.5 ? 1 : -1
            let top = size.height * (0.1 + 0.18 * rng.next())
            let progress = local / flight
            let span = size.width + 160
            let lead = direction > 0 ? -80 + progress * span : size.width + 80 - progress * span
            for k in 0..<5 {
                let row = Double((k + 1) / 2)
                let side: Double = k % 2 == 0 ? 1 : -1
                let x = lead - direction * row * 16
                let y = top + side * row * 9 + sin(time * 0.8 + Double(k)) * 2
                let flap = sin(time * 9 + Double(k) * 1.3)
                let s = 5.0
                var bird = Path()
                bird.move(to: CGPoint(x: x - s, y: y - flap * s * 0.6))
                bird.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: x - s * 0.5, y: y - s * 0.3 - flap * s * 0.3))
                bird.addQuadCurve(to: CGPoint(x: x + s, y: y - flap * s * 0.6),
                                  control: CGPoint(x: x + s * 0.5, y: y - s * 0.3 - flap * s * 0.3))
                gc.stroke(bird, with: .color(color),
                          style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Soft clouds that drift across the sky over a few minutes. Each puff is a radial gradient
/// squashed into an ellipse, so the edges are soft without a costly blur filter.
private struct CloudLayer: View {
    var time: Double
    var tint: Color = .white

    var body: some View {
        Canvas { gc, size in
            let clouds: [(y: Double, w: Double, speed: Double, offset: Double, alpha: Double)] = [
                (0.10, 0.55, 3.0, 0.0, 0.16), (0.22, 0.40, 2.2, 0.45, 0.12),
                (0.06, 0.35, 1.6, 0.75, 0.10), (0.30, 0.50, 2.6, 0.25, 0.08),
            ]
            func puff(center: CGPoint, width: Double, alpha: Double) {
                var g = gc
                g.translateBy(x: center.x, y: center.y)
                g.scaleBy(x: 1, y: 0.32)
                let r = width / 2
                g.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [tint.opacity(alpha), tint.opacity(alpha * 0.45), .clear]),
                                             center: .zero, startRadius: 0, endRadius: r))
            }
            for c in clouds {
                let span = size.width * (1 + c.w)
                let x = (time * c.speed + c.offset * span).truncatingRemainder(dividingBy: span) - size.width * c.w
                let w = size.width * c.w
                let center = CGPoint(x: x + w / 2, y: size.height * c.y + w * 0.11)
                puff(center: center, width: w * 1.25, alpha: c.alpha * 2.2)
                puff(center: CGPoint(x: center.x + w * 0.1, y: center.y - w * 0.06), width: w * 0.8, alpha: c.alpha * 1.8)
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
    var asr: Date?
    /// 0 = the sun is at the left, 1 = at the right. The city's edge on that side catches
    /// the warm light.
    var lightX: Double = 0.5

    var body: some View {
        let sky = SkyPalette.colors(at: date, sunrise: sunrise, sunset: sunset, asr: asr)
        ZStack(alignment: .bottom) {
            Image("HorizonCity")
                .resizable()
                .scaledToFit()
                .foregroundStyle(sky.cityColor)
                .overlay {
                    LinearGradient(colors: [sky.glow.opacity(0.5 * sky.warmth * min(1, sky.light * 2)), .clear],
                                   startPoint: UnitPoint(x: lightX, y: 0),
                                   endPoint: UnitPoint(x: 1 - lightX, y: 0.9))
                        .blendMode(.screen)
                        .mask(Image("HorizonCity").resizable().scaledToFit())
                }
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
