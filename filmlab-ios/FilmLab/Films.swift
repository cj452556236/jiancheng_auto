import Foundation
import simd

enum FilmKind { case slide, neg, bw, instant }

/// Which darkroom process a film is printed with.
enum Family: String, Codable {
    case neg, pos, bw

    var processTitle: String {
        switch self {
        case .neg: return "RA-4 彩色负片放大"
        case .pos: return "Ilfochrome 正片直接放大"
        case .bw: return "Multigrade 多级反差黑白相纸"
        }
    }

    var hint: String {
        switch self {
        case .neg: return "加 Y 偏蓝 · 加 M 偏绿 · 加 C 偏红 · 时间越长越暗"
        case .pos: return "加 Y 偏黄 · 加 M 偏品 · 加 C 偏青 · 时间越长越亮"
        case .bw: return "等级越高反差越大 · 时间越长越暗"
        }
    }

    /// Cast produced by adding (index 0) or removing (index 1) each filter.
    func cast(_ channel: String) -> (String, String) {
        switch (self, channel) {
        case (.neg, "y"): return ("偏蓝", "偏黄")
        case (.neg, "m"): return ("偏绿", "偏品")
        case (.neg, _): return ("偏红", "偏青")
        case (_, "y"): return ("偏黄", "偏蓝")
        case (_, "m"): return ("偏品", "偏绿")
        default: return ("偏青", "偏红")
        }
    }
}

struct FilmParams {
    var exp: Float = 0
    var wb: SIMD3<Float> = [1, 1, 1]
    var slope: SIMD3<Float> = [1, 1, 1]
    var offset: SIMD3<Float> = [0, 0, 0]
    var power: SIMD3<Float> = [1, 1, 1]
    var contrast: Float = 0
    var pivot: Float = 0.45
    var sat: Float = 1
    /// Hue bands r, y, g, c, b, m: (hue shift in degrees, saturation delta, value delta).
    var hsl: [String: SIMD3<Float>] = [:]
    var shadow: SIMD3<Float> = [0, 0, 0]
    var high: SIMD3<Float> = [0, 0, 0]
    var black: Float = 0
    var white: Float = 1
    var bw: SIMD3<Float>? = nil
    var grain: Float = 0.25
    var grainSize: Float = 1.1
    var grainColor: Float = 0.3
    var halation: Float = 0.12
    var halColor: SIMD3<Float> = [1, 0.32, 0.12]
    var halThresh: Float = 0.62
    var vignette: Float = 0.1
    var infrared = false
}

struct FilmStock: Identifiable {
    let id: String
    let name: String
    let dial: String
    let brand: String
    let code: String
    let kind: FilmKind
    let process: String
    let iso: Int
    let color: UInt32
    let desc: String
    let p: FilmParams

    init(_ id: String, _ name: String, _ dial: String, _ brand: String, _ code: String, _ kind: FilmKind,
         _ process: String, _ iso: Int, _ color: UInt32, _ desc: String,
         _ configure: (inout FilmParams) -> Void = { _ in }) {
        self.id = id
        self.name = name
        self.dial = dial
        self.brand = brand
        self.code = code
        self.kind = kind
        self.process = process
        self.iso = iso
        self.color = color
        self.desc = desc
        var params = FilmParams()
        configure(&params)
        self.p = params
    }

    var family: Family { kind == .bw ? .bw : (kind == .neg ? .neg : .pos) }

    var brandCN: String {
        switch brand {
        case "FUJIFILM": return "富士"
        case "KODAK": return "柯达"
        case "ILFORD": return "伊尔福"
        case "AGFA": return "爱克发"
        case "POLAROID": return "宝丽来"
        default: return "CineStill"
        }
    }

    var processCN: String {
        switch process {
        case "E-6": return "反转片 E-6"
        case "K-14": return "反转片 K-14"
        case "C-41": return "彩色负片 C-41"
        case "ECN-2": return "电影负片 ECN-2"
        case "B&W": return "黑白负片"
        default: return "一次成像"
        }
    }

    var mountName: String {
        if brand == "FUJIFILM" && kind == .slide { return "FUJICHROME" }
        if id == "kodachrome" { return "KODACHROME" }
        if id == "e100" { return "EKTACHROME" }
        return brand
    }
}

extension FilmStock {
    static let all: [FilmStock] = [
        FilmStock("velvia50", "Velvia 50", "VELVIA 50", "FUJIFILM", "RVP 50", .slide, "E-6", 50, 0x2F7A52,
                  "风光摄影的传奇反转片：极高饱和、反差厚重，绿叶浓郁、天空深邃。") { p in
            p.exp = -0.15; p.wb = [1.03, 1, 0.96]; p.contrast = 0.55; p.pivot = 0.42; p.sat = 1.38
            p.hsl = ["r": [-4, 0.15, -0.06], "y": [-6, 0.12, 0], "g": [4, 0.35, -0.1], "c": [0, 0.2, -0.06], "b": [3, 0.25, -0.15], "m": [0, 0.2, 0]]
            p.shadow = [0.006, -0.003, 0.006]; p.grain = 0.07; p.grainSize = 0.8; p.halation = 0.05
        },
        FilmStock("velvia100", "Velvia 100", "VELVIA 100", "FUJIFILM", "RVP100", .slide, "E-6", 100, 0x7B3F98,
                  "更鲜艳利落的 Velvia：红色带一点品红，蓝天更纯，颗粒细腻，风光与花卉的首选。") { p in
            p.exp = -0.1; p.wb = [1, 0.995, 1.005]; p.offset = [0.002, -0.002, 0]; p.contrast = 0.48; p.pivot = 0.43; p.sat = 1.38
            p.hsl = ["r": [-7, 0.2, -0.05], "y": [-3, 0.1, 0], "g": [3, 0.3, -0.07], "c": [-2, 0.2, -0.05], "b": [1, 0.25, -0.12], "m": [0, 0.15, 0]]
            p.shadow = [0.002, -0.002, 0.006]; p.grain = 0.07; p.grainSize = 0.8; p.halation = 0.05
        },
        FilmStock("provia", "Provia 100F", "PROVIA", "FUJIFILM", "RDP III", .slide, "E-6", 100, 0x2B65B0,
                  "标准中性的专业反转片：色彩准确、反差适中，什么都能拍。") { p in
            p.wb = [0.99, 1, 1.02]; p.contrast = 0.25; p.sat = 1.12
            p.hsl = ["g": [0, 0.06, 0], "b": [-2, 0.08, -0.04]]
            p.black = 0.008; p.grain = 0.08; p.grainSize = 0.8
        },
        FilmStock("astia", "Astia 100F", "ASTIA", "FUJIFILM", "RAP F", .slide, "E-6", 100, 0xC8607F,
                  "柔和反差的人像反转片：肤色细腻，高光过渡温柔。") { p in
            p.wb = [1.01, 1, 0.99]; p.contrast = 0.08; p.sat = 1.04
            p.hsl = ["r": [2, -0.05, 0.03], "y": [0, -0.05, 0.03], "b": [0, 0.1, -0.03]]
            p.high = [0.006, 0.003, -0.002]; p.black = 0.015; p.grain = 0.07; p.grainSize = 0.8
        },
        FilmStock("pro400h", "Pro 400H", "PRO 400H", "FUJIFILM", "PRO 400H", .neg, "C-41", 400, 0x6FAE8C,
                  "清新通透的婚礼胶片：粉彩色调，绿色偏薄荷青，阴影透着青蓝。") { p in
            p.exp = 0.15; p.wb = [0.98, 1.01, 1.02]; p.contrast = -0.12; p.sat = 0.88
            p.hsl = ["r": [0, -0.05, 0.03], "y": [6, -0.1, 0.04], "g": [12, -0.1, 0.06], "b": [-6, -0.05, 0.04]]
            p.shadow = [-0.01, 0.008, 0.012]; p.high = [0.01, 0.005, -0.005]; p.black = 0.04; p.white = 0.97; p.grain = 0.3; p.grainSize = 1.2
        },
        FilmStock("superia", "Superia 400", "SUPERIA", "FUJIFILM", "X-TRA 400", .neg, "C-41", 400, 0x2F9B54,
                  "富士经典民用负片：绿色偏青、色彩讨喜，带着街拍的颗粒感。") { p in
            p.contrast = 0.15; p.sat = 1.1
            p.hsl = ["r": [2, 0.08, 0], "g": [10, 0.05, -0.04], "c": [0, 0.1, -0.03], "b": [-4, 0.05, 0]]
            p.shadow = [-0.006, 0.01, 0.012]; p.high = [0.01, 0.004, -0.01]; p.black = 0.025; p.grain = 0.38; p.grainSize = 1.35
        },
        FilmStock("c200", "Fujicolor C200", "C200", "FUJIFILM", "C200", .neg, "C-41", 200, 0x3AA37A,
                  "入门民用负片：略带绿调，淡淡的复古感。") { p in
            p.wb = [0.98, 1.02, 0.99]; p.contrast = 0.08; p.sat = 0.98; p.hsl = ["g": [8, 0, 0]]
            p.shadow = [-0.005, 0.01, 0.006]; p.black = 0.03; p.grain = 0.32; p.grainSize = 1.25
        },
        FilmStock("chrome", "Classic Chrome", "CL.CHROME", "FUJIFILM", "CLASSIC CHROME", .slide, "E-6", 160, 0x8B877C,
                  "富士相机里的经典色彩：低饱和、阴影硬朗，蓝色偏青，像老杂志里的纪实照片。") { p in
            p.contrast = 0.22; p.sat = 0.78
            p.hsl = ["r": [-2, 0.05, -0.08], "y": [-4, -0.2, 0], "g": [-6, -0.3, -0.04], "c": [0, -0.1, 0], "b": [-14, -0.05, -0.08]]
            p.shadow = [-0.005, 0, 0.01]; p.high = [0.01, 0.005, -0.01]; p.black = 0.01; p.grain = 0.18; p.grainSize = 1
        },
        FilmStock("classicneg", "Classic Neg.", "CL.NEG", "FUJIFILM", "CLASSIC NEG", .neg, "C-41", 400, 0x4F7F8A,
                  "仿负片冲扫的影调：高光偏暖、阴影偏青，色彩分离强烈。") { p in
            p.contrast = 0.3; p.sat = 0.95
            p.hsl = ["r": [-6, 0.1, -0.06], "y": [4, -0.15, 0], "g": [16, -0.1, -0.06], "c": [0, 0.05, -0.05], "b": [-8, 0.05, -0.05]]
            p.shadow = [-0.01, 0.006, 0.014]; p.high = [0.02, 0.008, -0.012]; p.black = 0.025; p.white = 0.98; p.grain = 0.28; p.grainSize = 1.2
        },
        FilmStock("nostalgic", "Nostalgic Neg.", "NOSTALGIC", "FUJIFILM", "NOSTALGIC NEG", .neg, "C-41", 400, 0xC48A3E,
                  "琥珀色的高光、浓郁的暗部，70 年代美国新彩色摄影的味道。") { p in
            p.wb = [1.03, 1, 0.95]; p.contrast = 0.1; p.sat = 1
            p.hsl = ["r": [0, 0.1, 0], "y": [-4, 0.1, 0.03], "b": [0, -0.1, 0]]
            p.high = [0.03, 0.012, -0.03]; p.black = 0.025; p.grain = 0.25
        },
        FilmStock("eterna", "Eterna 250D", "ETERNA", "FUJIFILM", "ETERNA 250D", .neg, "ECN-2", 250, 0x4C6B7C,
                  "电影负片的低反差、低饱和影调，阴影带青，画面像电影截图。") { p in
            p.contrast = -0.25; p.sat = 0.72
            p.hsl = ["r": [0, -0.05, 0], "g": [8, -0.2, 0], "b": [-6, -0.1, 0]]
            p.shadow = [-0.008, 0.006, 0.01]; p.high = [0.006, 0.004, -0.004]; p.black = 0.035; p.white = 0.97; p.grain = 0.2
        },
        FilmStock("acros", "Neopan Acros 100", "ACROS", "FUJIFILM", "ACROS 100", .bw, "B&W", 100, 0x6D6A66,
                  "颗粒极细的黑白片：层次丰富，暗部干净。") { p in
            p.bw = [0.34, 0.56, 0.10]; p.contrast = 0.3; p.grain = 0.22; p.grainSize = 0.85; p.halation = 0.04
        },
        FilmStock("portra160", "Portra 160", "PORTRA 160", "KODAK", "PORTRA 160", .neg, "C-41", 160, 0xE9B44C,
                  "低反差、肤色自然的专业人像负片，适合光线充足的场景。") { p in
            p.contrast = -0.1; p.sat = 0.92; p.wb = [1.01, 1, 0.99]
            p.hsl = ["r": [3, -0.05, 0.03], "y": [-2, -0.05, 0.03], "g": [-6, -0.18, 0], "b": [-4, -0.05, 0.02]]
            p.shadow = [0.004, 0, 0.006]; p.high = [0.012, 0.006, -0.006]; p.black = 0.03; p.white = 0.975; p.grain = 0.18; p.grainSize = 0.95
        },
        FilmStock("portra400", "Portra 400", "PORTRA 400", "KODAK", "PORTRA 400", .neg, "C-41", 400, 0xF0B23C,
                  "最受欢迎的人像负片：暖调、奶油般的肤色，宽容度极高。") { p in
            p.exp = 0.1; p.contrast = -0.08; p.sat = 0.95; p.wb = [1.045, 1, 0.94]
            p.hsl = ["r": [4, -0.04, 0.04], "y": [-4, 0, 0.04], "g": [-10, -0.2, 0], "c": [-6, -0.1, 0], "b": [-6, -0.08, 0.02]]
            p.shadow = [0, 0.004, 0.01]; p.high = [0.025, 0.012, -0.015]; p.black = 0.035; p.white = 0.975; p.grain = 0.3; p.grainSize = 1.15
        },
        FilmStock("portra800", "Portra 800", "PORTRA 800", "KODAK", "PORTRA 800", .neg, "C-41", 800, 0xE0952E,
                  "高速人像负片：色彩更浓、颗粒更明显，夜景也能拍。") { p in
            p.contrast = 0.05; p.sat = 1.05; p.wb = [1.04, 1, 0.95]
            p.hsl = ["r": [4, 0.05, 0.03], "y": [-4, 0.05, 0.03], "g": [-10, -0.15, 0], "b": [-6, 0, 0]]
            p.shadow = [0.002, 0.004, 0.012]; p.high = [0.02, 0.01, -0.012]; p.black = 0.04; p.white = 0.975; p.grain = 0.45; p.grainSize = 1.5; p.halation = 0.2
        },
        FilmStock("ektar", "Ektar 100", "EKTAR", "KODAK", "EKTAR 100", .neg, "C-41", 100, 0xD9472D,
                  "号称颗粒最细的负片：饱和鲜艳，红色与蓝色尤其浓烈。") { p in
            p.contrast = 0.35; p.sat = 1.3; p.wb = [1, 1, 1.01]
            p.hsl = ["r": [-4, 0.25, -0.04], "y": [-2, 0.1, 0], "g": [-2, 0.1, -0.04], "c": [0, 0.15, 0], "b": [4, 0.25, -0.08]]
            p.black = 0.01; p.grain = 0.14; p.grainSize = 0.85
        },
        FilmStock("gold", "Gold 200", "GOLD", "KODAK", "GOLD 200", .neg, "C-41", 200, 0xF2B51B,
                  "金黄色的阳光感，民用负片里最有夏天味道的一卷。") { p in
            p.exp = 0.05; p.contrast = 0.12; p.sat = 1.08; p.wb = [1.06, 1.01, 0.9]
            p.hsl = ["r": [4, 0.05, 0], "y": [-6, 0.15, 0.04], "g": [-10, -0.05, 0], "b": [0, -0.05, 0]]
            p.high = [0.02, 0.012, -0.02]; p.black = 0.03; p.grain = 0.32; p.grainSize = 1.25
        },
        FilmStock("ultramax", "Ultramax 400", "ULTRAMAX", "KODAK", "UL 400", .neg, "C-41", 400, 0xE1501F,
                  "温暖鲜艳的民用负片，颗粒明显，日常随拍的老朋友。") { p in
            p.contrast = 0.18; p.sat = 1.12; p.wb = [1.04, 1, 0.93]
            p.hsl = ["r": [0, 0.1, 0], "y": [-4, 0.1, 0], "g": [-6, 0, 0], "b": [0, 0.05, -0.03]]
            p.shadow = [0.005, 0, 0.01]; p.black = 0.03; p.grain = 0.42; p.grainSize = 1.4
        },
        FilmStock("kodachrome", "Kodachrome 64", "K-CHROME", "KODAK", "KR 64", .slide, "K-14", 64, 0xD4A017,
                  "已停产的传奇反转片：深红、金黄、浓郁的蓝天，反差硬朗。") { p in
            p.contrast = 0.45; p.pivot = 0.42; p.sat = 1.18; p.wb = [1.03, 1, 0.96]
            p.hsl = ["r": [-6, 0.25, -0.1], "y": [-8, 0.12, 0], "g": [-8, -0.05, -0.06], "c": [0, 0, -0.04], "b": [-2, 0.15, -0.14]]
            p.shadow = [0.006, 0, -0.004]; p.grain = 0.16; p.grainSize = 0.9
        },
        FilmStock("e100", "Ektachrome E100", "E100", "KODAK", "E100", .slide, "E-6", 100, 0x3478C6,
                  "干净通透的现代反转片：色彩准确，略微偏冷。") { p in
            p.contrast = 0.3; p.sat = 1.15; p.wb = [0.98, 1, 1.03]
            p.hsl = ["g": [2, 0.08, 0], "c": [0, 0.1, 0], "b": [-4, 0.15, -0.06]]
            p.grain = 0.07; p.grainSize = 0.8
        },
        FilmStock("trix", "Tri-X 400", "TRI-X", "KODAK", "400TX", .bw, "B&W", 400, 0xE6C229,
                  "最经典的新闻纪实黑白片：颗粒粗犷、反差有力。") { p in
            p.bw = [0.30, 0.60, 0.10]; p.contrast = 0.55; p.pivot = 0.42; p.grain = 0.55; p.grainSize = 1.6; p.halation = 0.06
        },
        FilmStock("aerochrome", "Aerochrome III", "AEROCHROME", "KODAK", "AEROCHROME III", .slide, "E-6", 400, 0xC3307A,
                  "红外彩色航拍胶片：绿色植被会变成粉红与洋红。") { p in
            p.infrared = true; p.contrast = 0.3; p.sat = 1.2; p.grain = 0.35; p.grainSize = 1.2
        },
        FilmStock("hp5", "HP5 Plus 400", "HP5", "ILFORD", "HP5 PLUS", .bw, "B&W", 400, 0xCFC8B8,
                  "宽容度极高的经典黑白片：影调柔和，颗粒自然。") { p in
            p.bw = [0.28, 0.62, 0.10]; p.contrast = 0.25; p.black = 0.02; p.grain = 0.45; p.grainSize = 1.4
        },
        FilmStock("delta3200", "Delta 3200", "DELTA 3200", "ILFORD", "DELTA 3200", .bw, "B&W", 3200, 0xB8332B,
                  "超高感黑白片：颗粒粗大、暗部浓郁，属于夜晚与氛围。") { p in
            p.bw = [0.30, 0.58, 0.12]; p.contrast = 0.15; p.black = 0.04; p.grain = 0.85; p.grainSize = 2.2
        },
        FilmStock("cs800t", "CineStill 800T", "800T", "CINESTILL", "800T", .neg, "ECN-2", 800, 0xC8283A,
                  "去掉防光晕层的灯光型电影胶片：画面偏冷，高光周围泛起红色光晕。") { p in
            p.wb = [0.88, 0.98, 1.12]; p.contrast = 0.15; p.sat = 1.05
            p.hsl = ["r": [-6, 0.15, 0], "y": [-12, -0.05, 0], "g": [14, -0.1, -0.04], "c": [0, 0.1, 0], "b": [-6, 0.1, 0]]
            p.shadow = [-0.012, 0.004, 0.016]; p.high = [0.01, 0.004, -0.004]; p.black = 0.035; p.grain = 0.45; p.grainSize = 1.45
            p.halation = 0.85; p.halColor = [1, 0.16, 0.06]; p.halThresh = 0.5
        },
        FilmStock("cs50d", "CineStill 50D", "50D", "CINESTILL", "50D", .neg, "ECN-2", 50, 0xE4A53D,
                  "细腻的日光型电影胶片：干净、色彩自然，高光带一圈淡淡红晕。") { p in
            p.contrast = 0.12; p.sat = 1.05; p.wb = [0.99, 1, 1.02]; p.black = 0.02; p.grain = 0.12; p.grainSize = 0.8
            p.halation = 0.5; p.halColor = [1, 0.2, 0.08]; p.halThresh = 0.55
        },
        FilmStock("vista", "Vista 200", "VISTA", "AGFA", "VISTA 200", .neg, "C-41", 200, 0xC7333A,
                  "德系民用负片：红色饱满、色调明快。") { p in
            p.contrast = 0.2; p.sat = 1.15; p.wb = [1.02, 0.99, 0.98]
            p.hsl = ["r": [-4, 0.2, 0], "g": [8, 0.05, -0.04], "b": [-6, 0.1, -0.02]]
            p.shadow = [-0.004, 0, 0.01]; p.black = 0.03; p.grain = 0.3; p.grainSize = 1.2
        },
        FilmStock("polaroid", "Polaroid 600", "POLAROID", "POLAROID", "600", .instant, "INSTANT", 640, 0xEEE7DA,
                  "宝丽来一次成像：低反差、奶油色高光与青绿色的阴影。") { p in
            p.exp = 0.1; p.contrast = -0.25; p.sat = 0.82; p.wb = [1.03, 1, 0.95]
            p.hsl = ["r": [4, -0.05, 0], "g": [10, -0.2, 0], "b": [-10, -0.15, 0.04]]
            p.shadow = [-0.01, 0.01, 0.02]; p.high = [0.03, 0.02, -0.01]; p.black = 0.07; p.white = 0.95
            p.grain = 0.15; p.grainSize = 1; p.vignette = 0.35; p.halation = 0.1
        },
    ]

    /// Consecutive runs of the same brand, for the dial's inner ring.
    static let brandGroups: [(brand: String, start: Int, end: Int)] = {
        var groups: [(brand: String, start: Int, end: Int)] = []
        for (i, f) in all.enumerated() {
            if let last = groups.last, last.brand == f.brand {
                groups[groups.count - 1].end = i
            } else {
                groups.append((brand: f.brand, start: i, end: i))
            }
        }
        return groups
    }()
}

// MARK: - Darkroom

struct NeutralPack {
    var c: Float = 0
    var m: Float = 0
    var y: Float = 0
    var time: Float = 12
    var grade: Int = 3
}

struct PaperSurface {
    let name: String
    let black: Float
    let white: SIMD3<Float>
    let tex: Float
}

struct Toning {
    let name: String
    let amount: Float
    let s: SIMD3<Float>
    let m: SIMD3<Float>
    let h: SIMD3<Float>
}

enum DarkroomSpec {
    static func neutral(_ family: Family) -> NeutralPack {
        switch family {
        case .neg: return NeutralPack(c: 0, m: 50, y: 60, time: 12, grade: 3)
        case .pos: return NeutralPack(c: 0, m: 10, y: 20, time: 16, grade: 3)
        case .bw: return NeutralPack(c: 0, m: 0, y: 0, time: 12, grade: 3)
        }
    }

    static let papers: [(name: String, k: Float)] = [("Endura 柔和", -0.15), ("Crystal Archive", 0), ("Ultra 高反差", 0.22)]

    static let surfaces: [PaperSurface] = [
        PaperSurface(name: "光面", black: 0.012, white: [0.985, 0.985, 0.98], tex: 0),
        PaperSurface(name: "珍珠面", black: 0.03, white: [0.975, 0.973, 0.966], tex: 0.012),
        PaperSurface(name: "哑光", black: 0.06, white: [0.962, 0.958, 0.95], tex: 0.022),
    ]

    static let surfacesBW: [PaperSurface] = [
        PaperSurface(name: "RC 光面", black: 0.012, white: [0.985, 0.985, 0.98], tex: 0),
        PaperSurface(name: "纤维暖调", black: 0.02, white: [0.975, 0.958, 0.925], tex: 0.008),
        PaperSurface(name: "哑光", black: 0.055, white: [0.962, 0.958, 0.95], tex: 0.022),
    ]

    static let grades = ["00", "0", "1", "2", "3", "4", "5"]

    static let tones: [Toning] = [
        Toning(name: "不调色", amount: 0, s: [0, 0, 0], m: [0, 0, 0], h: [0, 0, 0]),
        Toning(name: "硒调", amount: 0.6, s: [0.10, 0.06, 0.09], m: [0.50, 0.47, 0.48], h: [0.97, 0.96, 0.95]),
        Toning(name: "棕调", amount: 0.9, s: [0.16, 0.09, 0.05], m: [0.62, 0.48, 0.34], h: [0.98, 0.93, 0.84]),
        Toning(name: "金调", amount: 0.7, s: [0.05, 0.07, 0.12], m: [0.44, 0.48, 0.56], h: [0.95, 0.96, 0.98]),
        Toning(name: "蓝晒", amount: 1, s: [0.03, 0.12, 0.30], m: [0.30, 0.50, 0.72], h: [0.93, 0.96, 0.98]),
    ]
}

// MARK: - Frames and aspect ratios

enum FrameKind: String, Codable, CaseIterable, Identifiable {
    case none, film35, film120, slide, print, instant
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无边框"
        case .film35: return "35mm 底片"
        case .film120: return "120 中画幅"
        case .slide: return "幻灯片框"
        case .print: return "暗房相纸"
        case .instant: return "拍立得"
        }
    }

    /// Long side over short side, when the frame dictates it.
    var fixedAspect: Double? {
        switch self {
        case .film35, .slide: return 1.5
        case .film120, .instant: return 1
        default: return nil
        }
    }
}

enum AspectKind: String, Codable, CaseIterable, Identifiable {
    case original, r32, r43, r11, r45, r169
    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原比例"
        case .r32: return "3:2"
        case .r43: return "4:3"
        case .r11: return "1:1"
        case .r45: return "4:5"
        case .r169: return "16:9"
        }
    }

    var value: Double? {
        switch self {
        case .original: return nil
        case .r32: return 1.5
        case .r43: return 4.0 / 3.0
        case .r11: return 1
        case .r45: return 1.25
        case .r169: return 16.0 / 9.0
        }
    }
}
