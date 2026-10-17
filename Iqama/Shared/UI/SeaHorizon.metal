#include <metal_stdlib>
using namespace metal;

// The sky and the sea for the tabletop pose. The fold is the horizon: the sky is above it and
// the sea is below it. Two passes:
// 1. `seaEnvFragment` integrates the atmosphere (Rayleigh, Mie, and ozone, with the shadow of
//    the Earth) into a small panorama. It runs only when the time changes.
// 2. `seaSceneFragment` draws the sky from the panorama, with the sun, the moon, and the stars,
//    and the sea with real waves, the sky reflection, and the sun glitter.

constant float PI_F = 3.14159265;

struct SeaVertexOut {
    float4 position [[position]];
};

vertex SeaVertexOut seaFullscreenVertex(uint vid [[vertex_id]]) {
    const float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    SeaVertexOut out;
    out.position = float4(corners[vid], 0, 1);
    return out;
}

// MARK: - Pass 1: the atmosphere

struct SeaEnvUniforms {
    float4 sun;      // xyz: the direction to the sun
    float4 params;   // x: exposure; yz: the size of the panorama in pixels
};

constant float RP = 6371e3;
constant float RA = 6471e3;
constant float3 KR = float3(5.5e-6, 13.0e-6, 22.4e-6);
constant float KM = 14e-6;
constant float HR = 8e3;
constant float HM = 1.2e3;
constant float G = 0.78;
constant float3 KO = float3(0.65e-6, 1.881e-6, 0.085e-6);

static float ozone(float h) { return max(0.0, 1.0 - abs(h - 25e3) / 15e3); }

static float exitSphere(float3 o, float3 d, float r) {
    float b = dot(o, d);
    float c = dot(o, o) - r * r;
    return -b + sqrt(max(b * b - c, 0.0));
}

static bool hitsPlanet(float3 o, float3 d) {
    float b = dot(o, d);
    float c = dot(o, o) - RP * RP;
    return b < 0.0 && b * b - c > 0.0;
}

static float3 atmosphere(float3 rd, float3 sun) {
    float3 ro = float3(0.0, RP + 20.0, 0.0);
    float tMax = exitSphere(ro, rd, RA);
    float mu = dot(rd, sun);
    float pR = 3.0 / (16.0 * PI_F) * (1.0 + mu * mu);
    float g2 = G * G;
    float pM = 3.0 / (8.0 * PI_F) * ((1.0 - g2) * (1.0 + mu * mu))
             / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * G * mu, 1.5));
    float3 sR = 0.0, sM = 0.0;
    float odR = 0.0, odM = 0.0, odO = 0.0, prev = 0.0;
    for (int i = 0; i < 20; i++) {
        // Short steps near the eye, where the air is dense; long steps far away.
        float f = float(i + 1) / 20.0;
        float t1 = tMax * f * f;
        float ds = t1 - prev;
        float tm = prev + ds * 0.5;
        prev = t1;
        float3 p = ro + rd * tm;
        float h = length(p) - RP;
        float dR = exp(-h / HR) * ds;
        float dM = exp(-h / HM) * ds;
        odR += dR; odM += dM; odO += ozone(h) * ds;
        if (hitsPlanet(p, sun)) continue;   // in the shadow of the Earth
        float ls = exitSphere(p, sun, RA) / 8.0;
        float lR = 0.0, lM = 0.0, lO = 0.0;
        for (int j = 0; j < 8; j++) {
            float3 q = p + sun * (ls * (float(j) + 0.5));
            float hq = max(length(q) - RP, 0.0);
            lR += exp(-hq / HR) * ls;
            lM += exp(-hq / HM) * ls;
            lO += ozone(hq) * ls;
        }
        float3 att = exp(-(KR * (odR + lR) + KM * 1.1 * (odM + lM) + KO * (odO + lO)));
        sR += dR * att;
        sM += dM * att;
    }
    // The constant terms are a simple model of multiple scattering. Without them the sky is too
    // dark when the sun is low.
    return 22.0 * ((pR + 0.07) * KR * sR + (pM + 0.02) * KM * sM);
}

fragment float4 seaEnvFragment(SeaVertexOut in [[stage_in]], constant SeaEnvUniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / u.params.yz;
    float az = (uv.x * 200.0 - 100.0) * PI_F / 180.0;
    float elD = 90.0 * uv.y * uv.y;
    float el = elD * PI_F / 180.0;
    float3 rd = float3(cos(el) * sin(az), sin(el), cos(el) * cos(az));
    float3 night = float3(0.0016, 0.0024, 0.0056) + float3(0.0050, 0.0036, 0.0024) * exp(-elD / 5.0);
    float3 c = 1.0 - exp(-u.params.x * (atmosphere(rd, u.sun.xyz) + night));
    return float4(min(c, float3(0.996)), 1.0);
}

// MARK: - Pass 2: the sky and the sea

struct SeaSceneUniforms {
    float4 sun;       // xyz: the direction to the sun; w: the elevation (radians) of the disk center
    float4 sunPx;     // xy: the disk center (x from the left, y above the horizon, in pixels); z: radius (radians); w: flattening
    float4 disk;      // rgb: the radiance of the disk after the exposure
    float4 moon;      // xyz: the direction to the moon; w: visibility
    float4 moonPx;    // xy: the disk center in pixels; z: the phase angle (radians)
    float4 moonLit;   // xy: the direction to the sun on the screen
    float4 moonCol;   // rgb: the radiance of the moon after the exposure
    float4 geo;       // x: width; y: the fold (pixels from the top); z: pixels per degree; w: horizontal focal length
    float4 geo2;      // x: the focal length of the sea; y: the display scale; z: the stars; w: the time in seconds
    float4 waves[32]; // xy: the direction; z: the wave number; w: the slope
};

static float3 envSample(texture2d<float> env, sampler s, float az, float el) {
    float2 uv = float2((az * 180.0 / PI_F + 100.0) / 200.0, sqrt(clamp(el * 180.0 / PI_F / 90.0, 0.0, 1.0)));
    float3 c = env.sample(s, uv).rgb;
    return -log(1.0 - min(c, float3(0.996)));
}

static float3 envDirection(texture2d<float> env, sampler s, float3 d) {
    return envSample(env, s, atan2(d.x, d.z), asin(clamp(d.y, 0.05, 1.0)));
}

static float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

// The light of a small bright source on water with a Gaussian slope distribution of variance s2.
static float3 glint(float3 n, float3 V, float3 L, float s2, float3 E) {
    float3 H = normalize(L + V);
    float hn = max(dot(H, n), 1e-3);
    float hn2 = hn * hn;
    float D = exp(-(1.0 - hn2) / (hn2 * 2.0 * s2)) / (2.0 * PI_F * s2 * hn2 * hn2);
    float F = 0.02 + 0.98 * pow(1.0 - max(dot(V, H), 0.0), 5.0);
    return E * F * D / (4.0 * max(dot(n, V), 0.08));
}

fragment float4 seaSceneFragment(SeaVertexOut in [[stage_in]],
                                 constant SeaSceneUniforms &u [[buffer(0)]],
                                 texture2d<float> env [[texture(0)]],
                                 sampler envSampler [[sampler(0)]]) {
    float2 fc = in.position.xy;
    float width = u.geo.x, fold = u.geo.y, ppd = u.geo.z, focal = u.geo.w;
    float seaF = u.geo2.x, scale = u.geo2.y, stars = u.geo2.z, time = u.geo2.w;
    float ta = (fc.x - width * 0.5) / focal;
    float az = atan(ta);
    float3 col;

    if (fc.y < fold) {
        // The sky. `ly` is the height above the horizon.
        float ly = fold - fc.y;
        float elD = ly / ppd;
        float el = min(elD, 89.9) * PI_F / 180.0;
        col = envSample(env, envSampler, az, el);

        if (stars > 0.0) {
            float2 g = float2(fc.x, ly) / (6.0 * scale);
            float2 id = floor(g);
            float2 f = fract(g) - 0.5;
            float h = hash21(id);
            if (h > 0.965) {
                float2 off = float2(hash21(id + 3.1), hash21(id + 7.7)) - 0.5;
                float dpx = length(f - off * 0.6) * 6.0 * scale;
                float b = pow(hash21(id + 1.3), 5.0) * 2.2 + 0.15;
                float tw = 0.8 + 0.2 * sin(time * (1.0 + 3.0 * h) + h * 40.0);
                float sz = 0.55 * scale;
                col += float3(0.86, 0.9, 1.0) * b * tw * exp(-dpx * dpx / (2.0 * sz * sz))
                     * stars * smoothstep(0.0, 10.0, elD);
            }
        }

        float moonVis = u.moon.w;
        if (moonVis > 0.0) {
            float2 md = (float2(fc.x, ly) - u.moonPx.xy) / (2.4 * ppd);
            float mr = length(md);
            float pa = u.moonPx.z;
            float3 sv = float3(u.moonLit.xy * sin(pa), cos(pa));
            if (mr < 1.0) {
                float3 n = float3(md.x, md.y, sqrt(1.0 - mr * mr));
                float lit = smoothstep(-0.03, 0.06, dot(n, sv));
                float edge = smoothstep(1.0, 0.94, mr);
                float maria = 0.86 + 0.14 * hash21(floor(md * 5.0));
                col += u.moonCol.rgb * (lit * maria + 0.025) * edge * moonVis;
            }
            col += u.moonCol.rgb * 0.035 * exp(-max(mr - 1.0, 0.0) * 0.7) * moonVis;
        }

        float sunR = u.sunPx.z, flat = u.sunPx.w;
        float rPx = sunR * 180.0 / PI_F * ppd;
        float2 sd = float2(fc.x - u.sunPx.x, (ly - u.sunPx.y) / flat) / rPx;
        float r = length(sd);
        float aa = 1.5 / rPx;
        float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
        float ld = 1.0 - 0.62 * (1.0 - sqrt(max(1.0 - r * r, 0.0)));   // limb darkening
        col += u.disk.rgb * ld * inside;
        col += u.disk.rgb * 0.0007 * exp(-max(r - 1.0, 0.0) * 0.8);
    } else {
        // The sea. The camera is 4 m above the water, and lines on the water parallel to the
        // horizon stay straight.
        float v = max(fc.y - fold, 0.5);
        float3 d = normalize(float3(ta, -v / seaF, 1.0));
        float z = 4.0 * seaF / v;
        // The waves use the same scale on the two axes. The sky scale is much wider on a tall
        // screen and stretches the waves into streaks. The light keeps the sky scale, so the
        // glitter stays below the sun.
        float2 p = float2((fc.x - width * 0.5) / seaF * z, z);
        float t = length(float3(p.x, 4.0, p.y));
        // The size of one pixel on the water. Waves smaller than a few pixels become roughness.
        float fp = max(4.0 * seaF / (v * v), z / seaF);
        float2 grad = 0.0;
        float vr = 0.0;
        for (int i = 0; i < 32; i++) {
            float4 w = u.waves[i];
            float lam = 6.2831853 / w.z;
            float keep = smoothstep(3.0, 8.0, lam / fp);
            float om = sqrt(9.81 * w.z + 0.000074 * w.z * w.z * w.z);
            float ph = w.z * dot(w.xy, p) - om * time + float(i) * 1.731;
            grad += w.xy * (w.w * cos(ph) * keep);
            vr += w.w * w.w * 0.5 * (1.0 - keep);
        }
        float3 n = normalize(float3(-grad.x, 1.0, -grad.y));
        float s2 = 0.0012 + vr;
        float3 V = -d;
        float3 R = reflect(d, n);
        R.y = abs(R.y);
        float3 sky = envDirection(env, envSampler, R);
        float F = 0.02 + 0.98 * pow(1.0 - max(dot(n, V), 0.0), 5.0);
        float3 zen = envSample(env, envSampler, 0.0, 55.0 * PI_F / 180.0);
        float3 body = float3(0.014, 0.085, 0.095) * zen
                    + float3(0.006, 0.040, 0.044) * u.disk.rgb * 0.0025 * max(u.sun.y, 0.0);
        col = mix(body, sky, F);

        float sunR = u.sunPx.z;
        float sunUp = smoothstep(-0.004, 0.004, u.sun.w + sunR * u.sunPx.w);
        float3 E = u.disk.rgb * PI_F * sunR * sunR * 2.5;
        col += glint(n, V, u.sun.xyz, s2 + sunR * sunR * 0.15, E) * sunUp;
        if (u.moon.w > 0.0 && u.moon.y > 0.0) {
            float mR = 2.4 * PI_F / 180.0;
            col += glint(n, V, u.moon.xyz, s2 + mR * mR * 0.15, u.moonCol.rgb * PI_F * mR * mR * 0.6) * u.moon.w;
        }
        float3 horizon = envSample(env, envSampler, az, 0.2 * PI_F / 180.0);
        col = mix(col, horizon, 1.0 - exp(-t / 6000.0));
    }

    // A filmic curve keeps the color of strong light near the sun.
    float3 x = col * 0.6;
    col = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
    col += (hash21(fc + fract(time * 7.0)) - 0.5) / 255.0;
    return float4(col, 1.0);
}
