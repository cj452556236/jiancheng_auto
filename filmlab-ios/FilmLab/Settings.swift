import Foundation
import simd

struct DarkroomSettings: Codable, Equatable {
    var family: Family = .pos
    var c: Float = 0
    var m: Float = 10
    var y: Float = 20
    var time: Float = 16
    var grade: Int = 3
    var paper: Int = 1
    var surface: Int = 0
    var tone: Int = 0

    static func neutral(for family: Family) -> DarkroomSettings {
        let n = DarkroomSpec.neutral(family)
        var d = DarkroomSettings()
        d.family = family
        d.c = n.c
        d.m = n.m
        d.y = n.y
        d.time = n.time
        d.grade = n.grade
        d.surface = family == .bw ? 1 : 0
        return d
    }
}

/// Everything the viewer can change. Persisted between launches.
struct FilmSettings: Codable, Equatable {
    var filmIndex = 1
    var ev: Float = 0
    var grain: Float? = nil
    var grainSize: Float? = nil
    var halation: Float? = nil
    var vignette: Float? = nil
    var bloom: Float = 0
    var leak: Float = 0
    var leakSeed = 7
    var dust: Float = 0
    var dateStamp = false
    var frame: FrameKind = .none
    var aspect: AspectKind = .original
    var dark = DarkroomSettings()
    var sound = true

    var film: FilmStock {
        FilmStock.all[min(max(filmIndex, 0), FilmStock.all.count - 1)]
    }

    var grainValue: Float { grain ?? film.p.grain }
    var grainSizeValue: Float { grainSize ?? film.p.grainSize }
    var halationValue: Float { halation ?? film.p.halation }
    var vignetteValue: Float { vignette ?? film.p.vignette }

    private static let key = "filmlab.settings.v1"

    static func load() -> FilmSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var s = try? JSONDecoder().decode(FilmSettings.self, from: data) else {
            return FilmSettings()
        }
        if s.dark.family != s.film.family { s.dark = .neutral(for: s.film.family) }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: FilmSettings.key)
        }
    }

    /// Exposure times shown on a five-band test strip.
    var stripTimes: [Float] {
        [-1, -0.5, 0, 0.5, 1].map { (o: Float) -> Float in dark.time * pow(2, o) }
    }

    var darkNote: String {
        if film.family == .bw {
            return "Grade \(DarkroomSpec.grades[min(max(dark.grade, 0), 6)]) · \(formatTime(dark.time)) · f/8"
        }
        let c = dark.c > 0 ? "C\(Int(dark.c)) " : ""
        return "\(c)M\(Int(dark.m)) Y\(Int(dark.y)) · \(formatTime(dark.time)) · f/8"
    }
}

func formatTime(_ t: Float) -> String {
    t < 10 ? String(format: "%.1fs", t) : "\(Int(t.rounded()))s"
}

/// Uniform block shared with Shaders.metal. Every member is a float4 so the
/// Swift and Metal layouts match exactly; keep the order identical.
struct FilmUniforms {
    var crop = SIMD4<Float>(0, 0, 1, 1)        // x, y, w, h in source uv (top-left origin)
    var res = SIMD4<Float>(1, 1, 0, 0)         // output w, h, grain seed, bypass
    var filmA = SIMD4<Float>(0, 0, 0.45, 1)    // exposure, contrast, pivot, saturation
    var filmB = SIMD4<Float>(0, 1, 0, 0)       // black, white, is b&w, halation
    var wb = SIMD4<Float>(1, 1, 1, 0)
    var slope = SIMD4<Float>(1, 1, 1, 0)
    var offset = SIMD4<Float>(0, 0, 0, 0)
    var power = SIMD4<Float>(1, 1, 1, 0)
    var hsl0 = SIMD4<Float>(0, 0, 0, 0)
    var hsl1 = SIMD4<Float>(0, 0, 0, 0)
    var hsl2 = SIMD4<Float>(0, 0, 0, 0)
    var hsl3 = SIMD4<Float>(0, 0, 0, 0)
    var hsl4 = SIMD4<Float>(0, 0, 0, 0)
    var hsl5 = SIMD4<Float>(0, 0, 0, 0)
    var shadowTint = SIMD4<Float>(0, 0, 0, 0)
    var highTint = SIMD4<Float>(0, 0, 0, 0)
    var bwMix = SIMD4<Float>(0, 0, 0, 0)
    var halColor = SIMD4<Float>(1, 0.32, 0.12, 0)
    var printGain = SIMD4<Float>(1, 1, 1, 0)
    var printParams = SIMD4<Float>(0, 0, 0, 1) // paper contrast, paper texture, test strip, strip sign
    var paperBlack = SIMD4<Float>(0, 0, 0, 0)
    var paperWhite = SIMD4<Float>(1, 1, 1, 0)
    var toneS = SIMD4<Float>(0, 0, 0, 0)
    var toneM = SIMD4<Float>(0, 0, 0, 0)
    var toneH = SIMD4<Float>(0, 0, 0, 0)
    var fx = SIMD4<Float>(0, 1, 0, 0)          // grain, grain size, grain colour, toning amount
    var fx2 = SIMD4<Float>(0, 0, 0, 0)         // vignette, light leak, dust, dark dust
    var fx3 = SIMD4<Float>(0, 0, 0.62, 0)      // bloom, infrared, halation threshold
}

struct CropRect {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var pixelWidth: Double
    var pixelHeight: Double

    var uniform: SIMD4<Float> { SIMD4<Float>(x, y, w, h) }
}

private func v4(_ v: SIMD3<Float>, _ w: Float = 0) -> SIMD4<Float> {
    SIMD4<Float>(v.x, v.y, v.z, w)
}

enum Pipeline {
    static func crop(width: Int, height: Int, settings s: FilmSettings) -> CropRect {
        let v: Double? = s.frame.fixedAspect ?? s.aspect.value
        let srcAr = Double(width) / Double(height)
        var cw = 1.0
        var ch = 1.0
        if let v {
            let ar = width >= height ? v : 1 / v
            if srcAr > ar { cw = ar / srcAr } else { ch = srcAr / ar }
        }
        return CropRect(x: Float((1 - cw) / 2), y: Float((1 - ch) / 2), w: Float(cw), h: Float(ch),
                        pixelWidth: Double(width) * cw, pixelHeight: Double(height) * ch)
    }

    static func printGain(_ s: FilmSettings, timeMultiplier: Float = 1) -> SIMD3<Float> {
        let family = s.film.family
        let n = DarkroomSpec.neutral(family)
        let d = s.dark
        let k: Float = 0.006
        let stops = log2(d.time * timeMultiplier / n.time)
        switch family {
        case .neg:
            let g = SIMD3<Float>(pow(10, (d.c - n.c) * k), pow(10, (d.m - n.m) * k), pow(10, (d.y - n.y) * k))
            return g * pow(2, -stops)
        case .pos:
            let g = SIMD3<Float>(pow(10, -(d.c - n.c) * k), pow(10, -(d.m - n.m) * k), pow(10, -(d.y - n.y) * k))
            return g * pow(2, stops)
        case .bw:
            return SIMD3<Float>(repeating: pow(2, -stops))
        }
    }

    static func uniforms(_ s: FilmSettings, crop: CropRect, width: Int, height: Int,
                         seed: Float, bypass: Bool = false, strip: Bool = false) -> FilmUniforms {
        let f = s.film
        let p = f.p
        let family = f.family
        let d = s.dark
        let surfaces = family == .bw ? DarkroomSpec.surfacesBW : DarkroomSpec.surfaces
        let surf = surfaces[min(max(d.surface, 0), surfaces.count - 1)]
        let tone = family == .bw ? DarkroomSpec.tones[min(max(d.tone, 0), DarkroomSpec.tones.count - 1)] : DarkroomSpec.tones[0]
        let paperK: Float = family == .bw ? Float(d.grade - 3) * 0.2 : DarkroomSpec.papers[min(max(d.paper, 0), 2)].k
        let bands: [SIMD4<Float>] = ["r", "y", "g", "c", "b", "m"].map { (key: String) -> SIMD4<Float> in
            let v = p.hsl[key] ?? SIMD3<Float>(0, 0, 0)
            return SIMD4<Float>(v.x / 360, v.y, v.z, 0)
        }
        let isBW: Float = p.bw != nil ? 1 : 0

        var u = FilmUniforms()
        u.crop = crop.uniform
        u.res = SIMD4<Float>(Float(width), Float(height), seed, bypass ? 1 : 0)
        u.filmA = SIMD4<Float>(p.exp + s.ev, min(max(p.contrast, -0.8), 2), p.pivot, p.sat)
        u.filmB = SIMD4<Float>(p.black, p.white, isBW, s.halationValue)
        u.wb = v4(p.wb)
        u.slope = v4(p.slope)
        u.offset = v4(p.offset)
        u.power = v4(p.power)
        u.hsl0 = bands[0]
        u.hsl1 = bands[1]
        u.hsl2 = bands[2]
        u.hsl3 = bands[3]
        u.hsl4 = bands[4]
        u.hsl5 = bands[5]
        u.shadowTint = v4(p.shadow)
        u.highTint = v4(p.high)
        u.bwMix = v4(p.bw ?? SIMD3<Float>(0, 0, 0))
        u.halColor = v4(p.halColor)
        u.printGain = v4(printGain(s))
        u.printParams = SIMD4<Float>(paperK, surf.tex, strip ? 1 : 0, family == .pos ? -1 : 1)
        u.paperBlack = SIMD4<Float>(surf.black, surf.black, surf.black, 0)
        u.paperWhite = v4(surf.white)
        u.toneS = v4(tone.s)
        u.toneM = v4(tone.m)
        u.toneH = v4(tone.h)
        u.fx = SIMD4<Float>(s.grainValue, s.grainSizeValue, p.bw != nil ? 0 : p.grainColor, tone.amount)
        u.fx2 = SIMD4<Float>(s.vignetteValue, s.leak, s.dust, family == .pos ? 1 : 0)
        u.fx3 = SIMD4<Float>(s.bloom, p.infrared ? 1 : 0, p.halThresh, 0)
        return u
    }
}
