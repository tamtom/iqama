import SwiftUI
import MetalKit

/// The sky over the sea, for the tabletop pose of iPhone Duo. The fold is the horizon: the sun
/// rises out of the sea on the right (east) and sets into it on the left (west), at the real
/// times of the day. The shaders are in `SeaHorizon.metal`.
struct SeaHorizonView: View {
    var date: Date
    var day: DailyPrayerTimes?
    var latitude: Double
    /// The horizon, in points from the top of the view.
    var foldY: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SeaMetalView(sky: SeaSky(date: date, day: day, latitude: latitude),
                     foldY: foldY,
                     animated: !reduceMotion)
            .accessibilityHidden(true)
    }
}

// MARK: - The sun and the moon

/// The positions and the colors of the sun and the moon at one moment. The sun crosses the
/// screen on the same arc as in the rest of the app; its height is the real solar altitude,
/// scaled so that its upper edge touches the horizon at the sunrise and at Maghrib.
struct SeaSky: Equatable {
    var sun: SIMD3<Float> = [0, -1, 0]
    var sunAzimuth: Double = 0          // degrees, positive to the right (east)
    var sunElevation: Double = -90      // degrees, the center of the drawn disk
    var sunRadius: Double = 1.4         // degrees, larger than the real sun so it shows
    var flattening: Double = 1
    var disk: SIMD3<Float> = .zero
    var exposure: Double = 1
    var moon: SIMD3<Float> = [0, -1, 0]
    var moonAzimuth: Double = 0
    var moonElevation: Double = -90
    var moonVisibility: Double = 0
    var moonPhaseAngle: Double = .pi
    var moonLit: SIMD2<Float> = [0, -1]
    var moonColor: SIMD3<Float> = .zero
    var stars: Double = 0

    init(date: Date, day: DailyPrayerTimes?, latitude: Double) {
        guard let day, let sunrise = day.sunriseTime, let maghrib = day.prayerTime(for: .maghrib),
              maghrib > sunrise else { return }
        let rad = Double.pi / 180
        let halfDay = maghrib.timeIntervalSince(sunrise) / 2
        let noon = sunrise.addingTimeInterval(halfDay)
        let dayOfYear = Double(Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1)
        let dec = -23.44 * cos(2 * .pi / 365 * (dayOfYear + 10)) * rad
        let lat = latitude * rad
        // The hour angle at which the altitude is -0.833°, the Awqaf sunrise and Maghrib.
        let cosH0 = (sin(-0.833 * rad) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
        let h0 = acos(min(1, max(-1, cosH0)))

        func trueAltitude(_ d: Date) -> Double {
            // Bring the time into the 24 hours around the solar noon.
            var dt = d.timeIntervalSince(noon).truncatingRemainder(dividingBy: 86_400)
            if dt > 43_200 { dt -= 86_400 } else if dt < -43_200 { dt += 86_400 }
            let h = dt / halfDay * h0
            return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)) / rad
        }
        func azimuth(_ d: Date) -> Double {
            var dt = d.timeIntervalSince(noon).truncatingRemainder(dividingBy: 86_400)
            if dt > 43_200 { dt -= 86_400 } else if dt < -43_200 { dt += 86_400 }
            let t = (dt + halfDay) / (2 * halfDay)
            if t < 0 { return 55 - t * 60 }
            if t > 1 { return -55 - (t - 1) * 60 }
            return 55 * cos(.pi * t)
        }
        func direction(_ az: Double, _ el: Double) -> SIMD3<Float> {
            let a = az * rad, e = el * rad
            return SIMD3(Float(cos(e) * sin(a)), Float(sin(e)), Float(cos(e) * cos(a)))
        }

        let alt = trueAltitude(date)
        let apparent = alt + Self.refraction(alt)
        flattening = 1 - 0.17 * exp(-max(apparent, 0) / 1.1)
        // The upper edge of the drawn disk is on the horizon at the sunrise and at Maghrib.
        sunElevation = apparent - (sunRadius * flattening - 0.266)
        sunAzimuth = azimuth(date)
        sun = direction(sunAzimuth, max(sunElevation, -89))
        exposure = Self.exposure(alt)
        let transmittance = Self.transmittance(sunElevation + sunRadius * flattening * 0.4)
        disk = transmittance * Float(exposure * 22 * 12)
        stars = Self.smoothstep(-7, -14, alt)

        // The moon follows the path of the sun, later by its phase: it is new with the sun and
        // full twelve hours after it.
        let phase = day.moonPhase - floor(day.moonPhase)
        let moonDate = date.addingTimeInterval(-phase * 24.84 * 3600)
        moonElevation = trueAltitude(moonDate)
        moonAzimuth = azimuth(moonDate)
        moon = direction(moonAzimuth, moonElevation)
        let elongation = phase * 360
        moonPhaseAngle = (180 - min(elongation, 360 - elongation)) * rad
        moonVisibility = moonElevation > -3 ? Self.smoothstep(3, -4, alt) : 0
        let lit = SIMD2(Float(sunAzimuth - moonAzimuth), Float(sunElevation - moonElevation))
        moonLit = simd_length(lit) > 0 ? simd_normalize(lit) : [0, -1]
        let zenith = Self.transmittance(90)
        moonColor = Self.transmittance(max(moonElevation, 0.2)) / zenith * Float(exposure * 0.12)
    }

    /// Atmospheric refraction in degrees (Sæmundsson), for the true altitude in degrees.
    static func refraction(_ h: Double) -> Double {
        let x = max(h, -1.2)
        return 1.02 / tan((x + 10.3 / (x + 5.11)) * .pi / 180) / 60
    }

    /// The part of the sunlight that comes through the air at this altitude. The constants are
    /// the same as in the shader.
    static func transmittance(_ altitude: Double) -> SIMD3<Float> {
        let rp = 6371e3, ra = 6471e3, oy = rp + 20
        let a = max(altitude, 0.15) * .pi / 180
        let dx = cos(a), dy = sin(a)
        let b = oy * dy, c = oy * oy - ra * ra
        let tMax = -b + sqrt(b * b - c)
        var prev = 0.0, odR = 0.0, odM = 0.0, odO = 0.0
        for i in 0..<128 {
            let f = Double(i + 1) / 128, t1 = tMax * f * f, ds = t1 - prev, tm = prev + ds / 2
            prev = t1
            let px = dx * tm, py = oy + dy * tm
            let h = (px * px + py * py).squareRoot() - rp
            odR += exp(-h / 8e3) * ds
            odM += exp(-h / 1.2e3) * ds
            odO += max(0, 1 - abs(h - 25e3) / 15e3) * ds
        }
        let kr = [5.5e-6, 13.0e-6, 22.4e-6], ko = [0.65e-6, 1.881e-6, 0.085e-6], km = 14e-6
        return SIMD3((0..<3).map { Float(exp(-(kr[$0] * odR + km * 1.1 * odM + ko[$0] * odO))) })
    }

    /// The exposure of the camera: higher when the sun is low, as the eye adapts to the dusk.
    static func exposure(_ altitude: Double) -> Double {
        let keys: [(Double, Double)] = [(30, 1.3), (12, 1.4), (4, 1.5), (0, 4.5), (-3, 12),
                                        (-6, 24), (-10, 38), (-14, 40), (-18, 38)]
        if altitude >= keys[0].0 { return keys[0].1 }
        for (a, b) in zip(keys, keys.dropFirst()) where altitude <= a.0 && altitude >= b.0 {
            let f = (a.0 - altitude) / (a.0 - b.0)
            return exp(log(a.1) + (log(b.1) - log(a.1)) * f)
        }
        return keys[keys.count - 1].1
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = min(1, max(0, (x - a) / (b - a)))
        return k * k * (3 - 2 * k)
    }
}

// MARK: - Metal

#if os(iOS)
private struct SeaMetalView: UIViewRepresentable {
    var sky: SeaSky
    var foldY: CGFloat
    var animated: Bool

    func makeCoordinator() -> SeaRenderer { SeaRenderer() }
    func makeUIView(context: Context) -> MTKView { context.coordinator.makeView() }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(view, sky: sky, foldY: foldY, animated: animated)
    }
}
#else
private struct SeaMetalView: NSViewRepresentable {
    var sky: SeaSky
    var foldY: CGFloat
    var animated: Bool

    func makeCoordinator() -> SeaRenderer { SeaRenderer() }
    func makeNSView(context: Context) -> MTKView { context.coordinator.makeView() }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(view, sky: sky, foldY: foldY, animated: animated)
    }
}
#endif

/// Draws the two passes. The atmosphere pass runs only when the sun moves; the sea pass runs
/// at 30 frames per second, or once per change with Reduce Motion.
final class SeaRenderer: NSObject, MTKViewDelegate {
    private var queue: MTLCommandQueue?
    private var envPipeline: MTLRenderPipelineState?
    private var scenePipeline: MTLRenderPipelineState?
    private var envTexture: MTLTexture?
    private var sampler: MTLSamplerState?
    private var envSky: SeaSky?
    private var sky: SeaSky?
    private var foldY: CGFloat = 0
    private var animated = true
    private let start = CACurrentMediaTime()
    private let waves = SeaRenderer.makeWaves()
    private static let envSize = (width: 1024, height: 384)

    func makeView() -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary() else { return view }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.delegate = self
        queue = device.makeCommandQueue()
        envPipeline = makePipeline(device, library, fragment: "seaEnvFragment", format: .rgba8Unorm)
        scenePipeline = makePipeline(device, library, fragment: "seaSceneFragment", format: view.colorPixelFormat)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: Self.envSize.width,
                                                            height: Self.envSize.height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        envTexture = device.makeTexture(descriptor: desc)

        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: s)
        return view
    }

    func update(_ view: MTKView, sky: SeaSky, foldY: CGFloat, animated: Bool) {
        self.sky = sky
        self.foldY = foldY
        self.animated = animated
        view.isPaused = !animated
        view.enableSetNeedsDisplay = !animated
        if !animated {
            #if os(iOS)
            view.setNeedsDisplay()
            #else
            view.needsDisplay = true
            #endif
        }
    }

    private func makePipeline(_ device: MTLDevice, _ library: MTLLibrary, fragment: String,
                              format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "seaFullscreenVertex")
        desc.fragmentFunction = library.makeFunction(name: fragment)
        desc.colorAttachments[0].pixelFormat = format
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// 32 waves from 34 m to 6 cm. The long waves come toward the shore; the short ones spread
    /// in more directions. The slopes give a wind of about 5 m/s.
    private static func makeWaves() -> [SIMD4<Float>] {
        var seed: UInt64 = 29
        func rnd() -> Double {
            seed = (seed * 16807) % 2_147_483_647
            return Double(seed) / 2_147_483_647
        }
        return (0..<32).map { i in
            let lam = 34 * pow(0.06 / 34, Double(i) / 31) * (0.8 + 0.4 * rnd())
            let spread = 0.45 + 1.6 * Double(i) / 31
            let a = 0.25 + (rnd() - 0.5) * spread
            return SIMD4(Float(sin(a)), Float(-cos(a)), Float(2 * Double.pi / lam), Float(0.026 + rnd() * 0.026))
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let sky, let queue, let envPipeline, let scenePipeline, let envTexture, let sampler,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), view.bounds.width > 0 else { return }

        if envSky != sky {
            let envPass = MTLRenderPassDescriptor()
            envPass.colorAttachments[0].texture = envTexture
            envPass.colorAttachments[0].loadAction = .dontCare
            envPass.colorAttachments[0].storeAction = .store
            if let encoder = buffer.makeRenderCommandEncoder(descriptor: envPass) {
                var uniforms: [SIMD4<Float>] = [
                    SIMD4(sky.sun, 0),
                    SIMD4(Float(sky.exposure), Float(Self.envSize.width), Float(Self.envSize.height), 0),
                ]
                encoder.setRenderPipelineState(envPipeline)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
            envSky = sky
        }

        let scale = Double(view.drawableSize.width / view.bounds.width)
        let width = Double(view.drawableSize.width)
        let fold = Double(foldY) * scale
        let ppd = fold / 106.6
        let focal = width * 0.2565
        let seaF = (Double(view.drawableSize.height) - fold) * 1.6
        func pixel(_ az: Double, _ el: Double) -> SIMD2<Float> {
            abs(az) > 85 ? [-9999, -9999] : [Float(width / 2 + focal * tan(az * .pi / 180)), Float(el * ppd)]
        }
        let time = animated ? CACurrentMediaTime() - start : 0
        let sunPx = pixel(sky.sunAzimuth, sky.sunElevation)
        let moonPx = pixel(sky.moonAzimuth, sky.moonElevation)
        let sunRow = SIMD4<Float>(sky.sun, Float(sky.sunElevation * .pi / 180))
        let sunShape = SIMD2<Float>(Float(sky.sunRadius * .pi / 180), Float(sky.flattening))
        let sunPxRow = SIMD4<Float>(lowHalf: sunPx, highHalf: sunShape)
        let moonRow = SIMD4<Float>(sky.moon, Float(sky.moonVisibility))
        let moonPxRow = SIMD4<Float>(lowHalf: moonPx, highHalf: [Float(sky.moonPhaseAngle), 0])
        let geo = SIMD4<Float>(Float(width), Float(fold), Float(ppd), Float(focal))
        let seconds = Float(time.truncatingRemainder(dividingBy: 3600))
        let geo2 = SIMD4<Float>(Float(seaF), Float(scale), Float(sky.stars), seconds)
        var uniforms: [SIMD4<Float>] = [sunRow, sunPxRow, SIMD4(sky.disk, 0), moonRow, moonPxRow,
                                        SIMD4(lowHalf: sky.moonLit, highHalf: .zero), SIMD4(sky.moonColor, 0), geo, geo2]
        uniforms += waves

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(scenePipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
            encoder.setFragmentTexture(envTexture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        buffer.present(drawable)
        buffer.commit()
    }
}

#Preview("Sunset over the sea") {
    GeometryReader { geo in
        SeaHorizonView(date: .now, day: nil, latitude: 25.2, foldY: geo.size.height / 2)
    }
    .ignoresSafeArea()
}
