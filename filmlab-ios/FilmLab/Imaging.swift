import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Small seeded generator so frames, borders and leaks look the same every render.
struct SeededRandom {
    private var state: UInt32

    init(seed: Int) {
        state = UInt32(truncatingIfNeeded: seed &* 7919 &+ 13)
    }

    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return CGFloat(t ^ (t >> 14)) / 4294967296.0
    }
}

enum ImageTools {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    /// Bakes the EXIF orientation into the pixels, converts to 8-bit sRGB and limits the long edge.
    static func upright(_ image: UIImage, maxLong: CGFloat) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let o = image.imageOrientation
        let swap = o == .left || o == .leftMirrored || o == .right || o == .rightMirrored
        let srcW = CGFloat(cg.width)
        let srcH = CGFloat(cg.height)
        let outW = swap ? srcH : srcW
        let outH = swap ? srcW : srcH
        let s = min(1, maxLong / max(outW, outH))
        let width = max(1, Int((outW * s).rounded()))
        let height = max(1, Int((outH * s).rounded()))
        guard let ctx = context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        let w = CGFloat(width)
        let h = CGFloat(height)
        var t = CGAffineTransform.identity
        switch o {
        case .down, .downMirrored:
            t = t.translatedBy(x: w, y: h).rotated(by: .pi)
        case .left, .leftMirrored:
            t = t.translatedBy(x: w, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            t = t.translatedBy(x: 0, y: h).rotated(by: -.pi / 2)
        default:
            break
        }
        switch o {
        case .upMirrored, .downMirrored:
            t = t.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            t = t.translatedBy(x: h, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }
        ctx.concatenate(t)
        let rect = swap ? CGRect(x: 0, y: 0, width: h, height: w) : CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(cg, in: rect)
        return ctx.makeImage()
    }

    static func downscale(_ image: CGImage, maxLong: CGFloat) -> CGImage? {
        let s = min(1, maxLong / CGFloat(max(image.width, image.height)))
        if s >= 1 { return image }
        let width = max(1, Int((CGFloat(image.width) * s).rounded()))
        let height = max(1, Int((CGFloat(image.height) * s).rounded()))
        guard let ctx = context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Square centre crop for the library button.
    static func thumbnail(_ image: CGImage, size: Int) -> CGImage? {
        guard let ctx = context(width: size, height: size) else { return nil }
        let s = max(CGFloat(size) / CGFloat(image.width), CGFloat(size) / CGFloat(image.height))
        let w = CGFloat(image.width) * s
        let h = CGFloat(image.height) * s
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, image, options)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// Procedural light-leak and dust plates, sampled by the shader.
enum Plates {
    static func leak(seed: Int) -> CGImage? {
        let size = 256
        guard let ctx = ImageTools.context(width: size, height: size) else { return nil }
        var r = SeededRandom(seed: seed)
        let s = CGFloat(size)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.setBlendMode(.plusLighter)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.31, 0.08), (1, 0.16, 0.08), (1, 0.67, 0.24), (1, 0.47, 0), (1, 0.84, 0.51)]
        let side = Int(r.next() * 4)
        for _ in 0..<4 {
            let along = s * (0.1 + r.next() * 0.8)
            let depth = s * (r.next() * 0.18 - 0.05)
            let px: CGFloat = side == 0 ? depth : (side == 1 ? s - depth : along)
            let py: CGFloat = side == 2 ? depth : (side == 3 ? s - depth : along)
            let radius = s * (0.22 + r.next() * 0.45)
            let c = colors[Int(r.next() * CGFloat(colors.count)) % colors.count]
            let a0 = 0.75 + r.next() * 0.25
            let a1 = 0.25 + r.next() * 0.2
            let cols = [CGColor(red: c.0, green: c.1, blue: c.2, alpha: a0),
                        CGColor(red: c.0, green: c.1, blue: c.2, alpha: a1),
                        CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0)] as CFArray
            guard let g = CGGradient(colorsSpace: ImageTools.sRGB, colors: cols, locations: [0, 0.45, 1]) else { continue }
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: px, y: py), startRadius: 0,
                                   endCenter: CGPoint(x: px, y: py), endRadius: radius, options: [])
        }
        return ctx.makeImage()
    }

    static func dust() -> CGImage? {
        let size = 1024
        guard let ctx = ImageTools.context(width: size, height: size) else { return nil }
        var r = SeededRandom(seed: 4242)
        let s = CGFloat(size)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        for _ in 0..<220 {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4 + r.next() * 0.6))
            let rad = 0.5 + r.next() * r.next() * 2.6
            let x = r.next() * s
            let y = r.next() * s
            ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
        }
        ctx.setLineCap(.round)
        for _ in 0..<14 {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55 + r.next() * 0.4))
            ctx.setLineWidth(0.7 + r.next() * 0.8)
            let sx = r.next() * s
            let sy = r.next() * s
            let l = 10 + r.next() * 40
            ctx.move(to: CGPoint(x: sx, y: sy))
            ctx.addCurve(to: CGPoint(x: sx + (r.next() - 0.5) * l * 1.5, y: sy + (r.next() - 0.5) * l * 1.5),
                         control1: CGPoint(x: sx + (r.next() - 0.5) * l, y: sy + (r.next() - 0.5) * l),
                         control2: CGPoint(x: sx + (r.next() - 0.5) * l, y: sy + (r.next() - 0.5) * l))
            ctx.strokePath()
        }
        for _ in 0..<4 {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.3 + r.next() * 0.3))
            ctx.setLineWidth(0.6)
            let sx = r.next() * s
            ctx.move(to: CGPoint(x: sx, y: 0))
            ctx.addCurve(to: CGPoint(x: sx + (r.next() - 0.5) * 20, y: s),
                         control1: CGPoint(x: sx + (r.next() - 0.5) * 30, y: s / 3),
                         control2: CGPoint(x: sx + (r.next() - 0.5) * 30, y: s * 2 / 3))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
