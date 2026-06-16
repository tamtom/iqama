import SwiftUI

// A full-bleed gradient sky that smoothly transitions through the day,
// layered with subtle Islamic 8-point star ornament and drifting starlight
// at night. Designed to be used as a `.background` on any container.
struct CelestialBackground: View {
    var animateOverTime: Bool = true
    var timeOverride: Date? = nil
    // [0,1]: where on screen the sun/moon currently sits. Drives the position
    // of the warm horizon halo so the theme appears to follow the celestial
    // body. Default 0.5 = centered.
    var bodyNormalizedX: Double = 0.5
    var bodyIsDay: Bool = true

    // Pauses the per-second sky refresh when the window is neither key nor
    // active (backgrounded / occluded), so a non-focused window renders a
    // single static frame at 0 fps instead of recompositing every second.
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        if let timeOverride {
            content(at: timeOverride)
        } else if animateOverTime && controlActiveState != .inactive {
            TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                content(at: ctx.date)
            }
        } else {
            content(at: Date())
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let sky = Theme.sky(at: date)
        let haloColor = bodyIsDay ? Theme.glowSoft : Color(red: 0.85, green: 0.90, blue: 1.00)
        ZStack {
            LinearGradient(
                colors: [sky.top, sky.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            // Soft warm halo — sun/moon glow anchored to the body's x position
            // so the theme visually follows the celestial body across the sky.
            RadialGradient(
                colors: [haloColor.opacity(haloOpacity(at: date)), .clear],
                center: .init(x: bodyNormalizedX, y: 0.40),
                startRadius: 4,
                endRadius: 420
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            // Subtle geometric ornament — almost invisible, just texture.
            IslamicStarOverlay()
                .opacity(0.06)
                .blendMode(.overlay)
                .allowsHitTesting(false)

            // Drifting starlight at night. Only mount the animated canvas when
            // it would actually be visible — a fully transparent StarField still
            // runs its render loop for nothing.
            if Theme.isNight(at: date) {
                let stars = starsOpacity(at: date)
                if stars > 0 {
                    StarField(seed: 1)
                        .opacity(stars)
                        .allowsHitTesting(false)
                }
            }

            // Bottom-up vignette — keeps content area dark enough for white
            // text even when the sky is at its brightest hue.
            LinearGradient(
                colors: [.clear, .black.opacity(0.10), .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 1.6), value: hourBucket(date))
    }

    private func hourBucket(_ d: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) / 5
    }

    private func haloOpacity(at date: Date) -> Double {
        // Steady baseline so the sun/moon always has a visible glow wash;
        // bumps slightly at sunrise/sunset for the warm-horizon effect.
        let cal = Calendar.current
        let t = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
        func bump(_ center: Double, _ width: Double) -> Double {
            let d = abs(t - center) / width
            return max(0, 1 - d * d)
        }
        return min(0.70, 0.32 + 0.40 * max(bump(6.0, 2.0), bump(18.2, 2.0)))
    }

    private func starsOpacity(at date: Date) -> Double {
        let cal = Calendar.current
        let t = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
        // Peak around midnight, fade out toward dawn / dusk.
        if t <= 5.0 { return max(0, 0.75 - t * 0.10) }   // 0.75 → 0.25
        if t >= 19.5 { return min(0.85, (t - 19.5) * 0.55 + 0.30) }
        return 0
    }
}

// A field of small, slowly drifting stars rendered with Canvas. Deterministic
// from `seed` so it doesn't flicker between frames.
struct StarField: View {
    var seed: UInt64 = 1
    var count: Int = 60

    // Freeze the twinkle when the window isn't focused/active. Without this the
    // `.animation` schedule keeps firing whether or not the window is visible —
    // the single biggest source of the app's background energy drain.
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        // 4 fps is visually indistinguishable from 30 for a slow drift/twinkle
        // (star motion has a multi-second period) but uses ~8× less power.
        TimelineView(.animation(minimumInterval: 1.0 / 4.0,
                                paused: controlActiveState == .inactive)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                var rng = SplitMix64(state: seed)
                for _ in 0..<count {
                    let x = Double(rng.nextUnitFloat()) * size.width
                    let y0 = Double(rng.nextUnitFloat()) * size.height * 0.85
                    let drift = Double(rng.nextUnitFloat()) * 18 - 9
                    let speed = 0.05 + Double(rng.nextUnitFloat()) * 0.15
                    let radius = 0.5 + Double(rng.nextUnitFloat()) * 1.6
                    let twinklePhase = Double(rng.nextUnitFloat()) * 6.28
                    let opacity = 0.45 + 0.45 * sin(phase * speed * 2 + twinklePhase)

                    let y = y0 + sin(phase * 0.05 + twinklePhase) * drift
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity * 0.9)))
                }
            }
        }
    }
}

// Deterministic, fast PRNG so star placement is stable across frames.
private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
    mutating func nextUnitFloat() -> Float {
        Float(next() & 0x00FFFFFF) / Float(0x01000000)
    }
}
