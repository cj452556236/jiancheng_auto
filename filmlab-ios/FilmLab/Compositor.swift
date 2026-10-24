import Foundation
import CoreGraphics
import CoreText
import UIKit

struct FrameLayout {
    var kind: FrameKind
    var W: Int
    var H: Int
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var mm: CGFloat = 1
    var rot = false
    var WL: CGFloat = 0
    var HL: CGFloat = 0
    var ixL: CGFloat = 0
    var iyL: CGFloat = 0
    var lw: CGFloat = 0
    var lh: CGFloat = 0
    var margin: CGFloat = 0

    var imageRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    static func make(_ kind: FrameKind, _ iw: Int, _ ih: Int) -> FrameLayout {
        let fw = CGFloat(iw)
        let fh = CGFloat(ih)
        switch kind {
        case .film35, .film120:
            let is35 = kind == .film35
            let rot = is35 && ih > iw
            let lw = rot ? fh : fw
            let lh = rot ? fw : fh
            let mm = is35 ? lw / 36 : lw / 56
            let wl = ((is35 ? 42 : 64) * mm).rounded()
            let hl = ((is35 ? 35 : 61) * mm).rounded()
            let ixL = ((wl - lw) / 2).rounded()
            let iyL = ((hl - lh) / 2).rounded()
            var L = FrameLayout(kind: kind, W: Int(wl), H: Int(hl), x: Int(ixL), y: Int(iyL), w: iw, h: ih)
            L.mm = mm
            L.rot = rot
            L.WL = wl
            L.HL = hl
            L.ixL = ixL
            L.iyL = iyL
            L.lw = lw
            L.lh = lh
            if rot {
                L.W = Int(hl)
                L.H = Int(wl)
                L.x = Int(hl - iyL - lh)
                L.y = Int(ixL)
            }
            return L
        case .slide:
            let mm = max(fw, fh) / 34.5
            let side = (50 * mm).rounded()
            var L = FrameLayout(kind: kind, W: Int(side), H: Int(side),
                                x: Int(((side - fw) / 2).rounded()), y: Int(((side - fh) / 2).rounded()), w: iw, h: ih)
            L.mm = mm
            return L
        case .print:
            let m = (max(fw, fh) * 0.07).rounded()
            let mb = (m * 1.55).rounded()
            var L = FrameLayout(kind: kind, W: iw + Int(2 * m), H: ih + Int(m + mb), x: Int(m), y: Int(m), w: iw, h: ih)
            L.margin = m
            return L
        case .instant:
            let mm = fw / 79
            var L = FrameLayout(kind: kind, W: Int((88 * mm).rounded()), H: Int((107 * mm).rounded()),
                                x: Int((4.5 * mm).rounded()), y: Int((6 * mm).rounded()), w: iw, h: ih)
            L.mm = mm
            return L
        case .none:
            return FrameLayout(kind: .none, W: iw, H: ih, x: 0, y: 0, w: iw, h: ih)
        }
    }
}

struct FrameMeta {
    var film: FilmStock
    var settings: FilmSettings
    var date: Date
    var frameNo: Int
    var seed: Int

    var dateText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
}

/// Draws frames around a rendered photo. Works in a top-left origin space like the web canvas.
enum Compositor {
    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func condensed(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> CTFont {
        UIFont.systemFont(ofSize: max(size, 1), weight: weight, width: .condensed) as CTFont
    }

    private static func mono(_ size: CGFloat) -> CTFont {
        UIFont.monospacedSystemFont(ofSize: max(size, 1), weight: .semibold) as CTFont
    }

    private static func hand(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("BradleyHandITCTT-Bold" as CFString, max(size, 1), nil)
    }

    private enum Align { case left, center, right }

    /// Draws one line of text whose vertical centre sits on `point.y`.
    private static func text(_ ctx: CGContext, _ string: String, _ font: CTFont, _ fill: CGColor,
                             _ point: CGPoint, _ align: Align = .left) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var x = point.x
        if align == .center { x -= width / 2 }
        if align == .right { x -= width }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: point.y + (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func textWidth(_ string: String, _ font: CTFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func drawImage(_ ctx: CGContext, _ image: CGImage, _ rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func compose(image: CGImage, layout L: FrameLayout, meta: FrameMeta, stripTimes: [Float]?) -> CGImage? {
        guard let ctx = ImageTools.context(width: L.W, height: L.H) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(L.H))
        ctx.scaleBy(x: 1, y: -1)
        switch L.kind {
        case .film35, .film120: drawFilmStrip(ctx, L, meta)
        case .slide: drawSlideMount(ctx, L, meta)
        case .print: drawPrintPaper(ctx, L, meta)
        case .instant: drawInstant(ctx, L, meta)
        case .none: break
        }
        drawImage(ctx, image, L.imageRect)
        if L.kind == .film120 { drawNotches(ctx, L) }
        if L.kind == .instant { drawInstantShadow(ctx, L) }
        if meta.settings.dateStamp { drawDateStamp(ctx, L, meta.date) }
        if let stripTimes { drawStripLabels(ctx, L, stripTimes) }
        return ctx.makeImage()
    }

    // MARK: Film strips

    private static func drawFilmStrip(_ ctx: CGContext, _ L: FrameLayout, _ meta: FrameMeta) {
        let f = meta.film
        let mm = L.mm
        let W = L.WL
        let H = L.HL
        ctx.saveGState()
        if L.rot {
            ctx.translateBy(x: CGFloat(L.W), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.setFillColor(color(f.kind == .bw ? 0x121212 : 0x0D0B0A))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let ink = f.kind == .bw ? color(0xDEDAD2, 0.85) : color(0xF3A03C, 0.92)
        if L.kind == .film35 {
            let pitch = 4.75 * mm
            let pw = 2.8 * mm
            let ph = 1.98 * mm
            let r = 0.5 * mm
            ctx.setFillColor(color(0xEFE9DC))
            var px = L.ixL - 1.9 * mm - pitch * 3
            while px < W {
                if px + pw >= 0 {
                    ctx.addPath(CGPath(roundedRect: CGRect(x: px, y: 2 * mm, width: pw, height: ph), cornerWidth: r, cornerHeight: r, transform: nil))
                    ctx.addPath(CGPath(roundedRect: CGRect(x: px, y: H - 2 * mm - ph, width: pw, height: ph), cornerWidth: r, cornerHeight: r, transform: nil))
                }
                px += pitch
            }
            ctx.fillPath()
            let font = condensed(1.3 * mm)
            text(ctx, "\(f.brand)  \(f.code)", font, ink, CGPoint(x: L.ixL + 2 * mm, y: 4.78 * mm))
            text(ctx, f.code, font, ink, CGPoint(x: L.ixL + 25 * mm, y: 4.78 * mm))
            text(ctx, "\(meta.frameNo)", font, ink, CGPoint(x: L.ixL + 7 * mm, y: H - 4.78 * mm))
            text(ctx, "\u{25B8} \(meta.frameNo)A", font, ink, CGPoint(x: L.ixL + 27 * mm, y: H - 4.78 * mm))
        } else {
            let font = condensed(1.5 * mm)
            text(ctx, "\(f.brand)  \(f.name.uppercased())", font, ink, CGPoint(x: L.ixL + 3 * mm, y: L.iyL / 2))
            text(ctx, "\u{25C0} \(meta.frameNo)", font, ink, CGPoint(x: L.ixL + L.lw - 3 * mm, y: L.iyL / 2), .right)
            text(ctx, "\(meta.frameNo)", font, ink, CGPoint(x: L.ixL + 20 * mm, y: H - L.iyL / 2))
        }
        ctx.restoreGState()
    }

    private static func drawNotches(_ ctx: CGContext, _ L: FrameLayout) {
        let mm = L.mm
        let x = CGFloat(L.x)
        let y = CGFloat(L.y)
        ctx.setFillColor(color(0x0D0B0A))
        ctx.move(to: CGPoint(x: x, y: y + 9 * mm))
        ctx.addLine(to: CGPoint(x: x + 1.4 * mm, y: y + 10 * mm))
        ctx.addLine(to: CGPoint(x: x, y: y + 11 * mm))
        ctx.closePath()
        ctx.move(to: CGPoint(x: x, y: y + 14 * mm))
        ctx.addLine(to: CGPoint(x: x + 0.9 * mm, y: y + 14.6 * mm))
        ctx.addLine(to: CGPoint(x: x, y: y + 15.2 * mm))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: Slide mount

    private static func drawSlideMount(_ ctx: CGContext, _ L: FrameLayout, _ meta: FrameMeta) {
        let f = meta.film
        let mm = L.mm
        let S = CGFloat(L.W)
        ctx.setFillColor(color(0x121110))
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0.5 * mm, y: 0.5 * mm, width: S - mm, height: S - mm),
                           cornerWidth: 3 * mm, cornerHeight: 3 * mm, transform: nil))
        ctx.clip()
        let cols = [color(0xF4F1EA), color(0xDEDAD1)] as CFArray
        if let g = CGGradient(colorsSpace: ImageTools.sRGB, colors: cols, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: S, y: S), options: [])
        }
        ctx.restoreGState()
        ctx.setStrokeColor(color(0x000000, 0.08))
        ctx.setLineWidth(0.25 * mm)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1.8 * mm, y: 1.8 * mm, width: S - 3.6 * mm, height: S - 3.6 * mm),
                           cornerWidth: 2.2 * mm, cornerHeight: 2.2 * mm, transform: nil))
        ctx.strokePath()
        ctx.setFillColor(color(0x000000, 0.22))
        ctx.fill(CGRect(x: CGFloat(L.x) - 0.5 * mm, y: CGFloat(L.y) - 0.5 * mm, width: CGFloat(L.w) + mm, height: CGFloat(L.h) + mm))

        let ink = f.brand == "FUJIFILM" ? color(0x2D7A46) : (f.brand == "KODAK" ? color(0xB8392A) : color(0x3B3A36))
        let grey = color(0x55524C)
        let top = CGFloat(L.y)
        let bottom = CGFloat(L.y + L.h)
        text(ctx, f.mountName, condensed(min(3.2 * mm, top * 0.42), .bold), ink, CGPoint(x: S / 2, y: top * 0.42), .center)
        text(ctx, f.name.uppercased(), condensed(min(2 * mm, top * 0.26)), grey, CGPoint(x: S / 2, y: top * 0.78), .center)
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let c = Calendar.current.dateComponents([.year, .month], from: meta.date)
        let small = condensed(min(2 * mm, (S - bottom) * 0.26))
        let mid = bottom + (S - bottom) * 0.5
        text(ctx, "\(months[max(0, min(11, (c.month ?? 1) - 1))]) \(c.year ?? 2026)", small, grey, CGPoint(x: 4 * mm, y: mid))
        text(ctx, "\u{2116} \(meta.frameNo)", small, grey, CGPoint(x: S - 4 * mm, y: mid), .right)
    }

    // MARK: Darkroom print

    private static func drawPrintPaper(_ ctx: CGContext, _ L: FrameLayout, _ meta: FrameMeta) {
        let surfaces = meta.film.family == .bw ? DarkroomSpec.surfacesBW : DarkroomSpec.surfaces
        let surf = surfaces[min(max(meta.settings.dark.surface, 0), surfaces.count - 1)]
        ctx.setFillColor(CGColor(red: CGFloat(surf.white.x), green: CGFloat(surf.white.y), blue: CGFloat(surf.white.z), alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: L.W, height: L.H))

        // Black border from a hand-filed negative carrier.
        let b = max(2, (CGFloat(max(L.w, L.h)) * 0.011).rounded())
        var r = SeededRandom(seed: meta.seed + 99)
        let step = max(2, b * 0.7)
        var points: [CGPoint] = []
        func edge(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ nx: CGFloat, _ ny: CGFloat) {
            let len = hypot(x1 - x0, y1 - y0)
            let n = max(2, Int((len / step).rounded()))
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                var o = b * (0.75 + r.next() * 0.45)
                if r.next() < 0.05 { o += b * (0.6 + r.next()) }
                if t < 0.06 || t > 0.94 { o += b * r.next() * 1.6 }
                points.append(CGPoint(x: x0 + (x1 - x0) * t + nx * o, y: y0 + (y1 - y0) * t + ny * o))
            }
        }
        let x = CGFloat(L.x)
        let y = CGFloat(L.y)
        let w = CGFloat(L.w)
        let h = CGFloat(L.h)
        edge(x, y, x + w, y, 0, -1)
        edge(x + w, y, x + w, y + h, 1, 0)
        edge(x + w, y + h, x, y + h, 0, 1)
        edge(x, y + h, x, y, -1, 0)
        if let first = points.first {
            ctx.move(to: first)
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.setFillColor(color(0x0E0D0C))
            ctx.fillPath()
        }

        let font = hand(max(9, (L.margin * 0.34).rounded()))
        let pencil = color(0x5F5A52, 0.85)
        let lineY = y + h + (CGFloat(L.H) - y - h) * 0.52
        text(ctx, "\(meta.film.name)  ·  \(meta.settings.darkNote)", font, pencil, CGPoint(x: x, y: lineY))
        text(ctx, meta.dateText, font, pencil, CGPoint(x: x + w, y: lineY), .right)
    }

    // MARK: Instant

    private static func drawInstant(_ ctx: CGContext, _ L: FrameLayout, _ meta: FrameMeta) {
        let cols = [color(0xF3F0E9), color(0xE9E5DC)] as CFArray
        if let g = CGGradient(colorsSpace: ImageTools.sRGB, colors: cols, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: L.H), options: [])
        }
        ctx.setFillColor(color(0x1A1816))
        ctx.fill(L.imageRect.insetBy(dx: -1, dy: -1))
        let font = hand(max(10, (L.mm * 6).rounded()))
        let y = CGFloat(L.y + L.h) + (CGFloat(L.H - L.y - L.h)) * 0.48
        text(ctx, "\(meta.film.name) · \(meta.dateText)", font, color(0x28375A, 0.85),
             CGPoint(x: CGFloat(L.x + L.w) - 2 * L.mm, y: y), .right)
    }

    private static func drawInstantShadow(_ ctx: CGContext, _ L: FrameLayout) {
        let s = max(2, L.mm * 1.2)
        let cols = [color(0x000000, 0.35), color(0x000000, 0)] as CFArray
        guard let g = CGGradient(colorsSpace: ImageTools.sRGB, colors: cols, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: CGFloat(L.x), y: CGFloat(L.y), width: CGFloat(L.w), height: s))
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(L.y)), end: CGPoint(x: 0, y: CGFloat(L.y) + s), options: [])
        ctx.restoreGState()
    }

    // MARK: Date stamp

    private static let segments: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
        "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    ]

    /// Seven-segment digits like a camera date back. Returns the drawn width.
    @discardableResult
    private static func sevenSegment(_ ctx: CGContext?, _ string: String, _ ox: CGFloat, _ oy: CGFloat, _ h: CGFloat) -> CGFloat {
        let w = h * 0.52
        let t = h * 0.13
        let sk = h * 0.12
        var cx = ox
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: cx + px + sk * (1 - py / h), y: oy + py)
        }
        let seg: [Character: (CGPoint, CGPoint)] = [
            "a": (CGPoint(x: t, y: 0), CGPoint(x: w - t, y: 0)),
            "b": (CGPoint(x: w, y: t), CGPoint(x: w, y: h / 2 - t / 2)),
            "c": (CGPoint(x: w, y: h / 2 + t / 2), CGPoint(x: w, y: h - t)),
            "d": (CGPoint(x: t, y: h), CGPoint(x: w - t, y: h)),
            "e": (CGPoint(x: 0, y: h / 2 + t / 2), CGPoint(x: 0, y: h - t)),
            "f": (CGPoint(x: 0, y: t), CGPoint(x: 0, y: h / 2 - t / 2)),
            "g": (CGPoint(x: t, y: h / 2), CGPoint(x: w - t, y: h / 2)),
        ]
        ctx?.setLineWidth(t)
        ctx?.setLineCap(.round)
        for ch in string {
            if ch == " " { cx += w * 0.9; continue }
            if ch == "'" {
                let a = point(w * 0.2, 0)
                let b = point(w * 0.1, h * 0.28)
                ctx?.move(to: a)
                ctx?.addLine(to: b)
                ctx?.strokePath()
                cx += w * 0.55
                continue
            }
            for s in segments[ch] ?? "" {
                guard let pair = seg[s] else { continue }
                ctx?.move(to: point(pair.0.x, pair.0.y))
                ctx?.addLine(to: point(pair.1.x, pair.1.y))
                ctx?.strokePath()
            }
            cx += w + h * 0.3
        }
        return cx - ox
    }

    private static func drawDateStamp(_ ctx: CGContext, _ L: FrameLayout, _ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let string = String(format: "'%02d %02d %02d", (c.year ?? 2026) % 100, c.month ?? 1, c.day ?? 1)
        let h = max(8, CGFloat(min(L.w, L.h)) * 0.042)
        let width = sevenSegment(nil, string, 0, 0, h)
        let ox = CGFloat(L.x + L.w) - width - CGFloat(L.w) * 0.04
        let oy = CGFloat(L.y + L.h) - h - CGFloat(L.h) * 0.05
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setShadow(offset: .zero, blur: h * 0.45, color: color(0xFF6E1E, 0.9))
        ctx.setStrokeColor(color(0xFF7828, 0.55))
        sevenSegment(ctx, string, ox, oy, h)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(color(0xFFBE6E, 0.85))
        sevenSegment(ctx, string, ox, oy, h)
        ctx.restoreGState()
    }

    // MARK: Test strip labels

    private static func drawStripLabels(_ ctx: CGContext, _ L: FrameLayout, _ times: [Float]) {
        let bw = CGFloat(L.w) / 5
        let fs = max(10, (CGFloat(L.h) * 0.05).rounded())
        let font = mono(fs)
        for i in 0..<5 {
            if i > 0 {
                ctx.setFillColor(color(0x000000, 0.55))
                ctx.fill(CGRect(x: CGFloat(L.x) + bw * CGFloat(i) - 1, y: CGFloat(L.y), width: 2, height: CGFloat(L.h)))
            }
            let label = formatTime(times[i])
            let cx = CGFloat(L.x) + bw * (CGFloat(i) + 0.5)
            let cy = CGFloat(L.y) + fs * 1.2
            let tw = textWidth(label, font) + fs * 0.8
            ctx.setFillColor(color(0x0A0807, 0.75))
            ctx.fill(CGRect(x: cx - tw / 2, y: cy - fs * 0.75, width: tw, height: fs * 1.5))
            text(ctx, label, font, i == 2 ? color(0xF2A63B) : color(0xE8E1D4), CGPoint(x: cx, y: cy), .center)
        }
    }
}
