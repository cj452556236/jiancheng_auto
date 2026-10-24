import SwiftUI
import UIKit
import AudioToolbox

private func wrapPi(_ a: CGFloat) -> CGFloat {
    var x = (a + .pi).truncatingRemainder(dividingBy: .pi * 2)
    if x < 0 { x += .pi * 2 }
    return x - .pi
}

/// The engraved film-simulation dial: drag or fling it, it clicks into each detent.
final class DialUIView: UIView {
    var onPick: ((Int) -> Void)?
    var soundEnabled = true
    private(set) var index = 0
    private(set) var isInteracting = false

    private var angle: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastAngle: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var tweenFrom: CGFloat = 0
    private var tweenTo: CGFloat = 0
    private var tweenStart: CFTimeInterval = 0
    private var tweenDuration: CFTimeInterval = 0
    private var coasting = false
    private var lastTick: CFTimeInterval = 0
    private let selection = UISelectionFeedbackGenerator()

    private var count: Int { FilmStock.all.count }
    private var step: CGFloat { .pi * 2 / CGFloat(count) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "胶片模拟转盘"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var accessibilityValue: String? {
        get { FilmStock.all[index].name }
        set { }
    }

    override func accessibilityIncrement() { go(to: index + 1) }
    override func accessibilityDecrement() { go(to: index - 1) }

    private var geometry: (r: CGFloat, cx: CGFloat, cy: CGFloat) {
        let r = max(bounds.width * 0.9, 300)
        return (r, bounds.width / 2, 30 + r)
    }

    private func angleAt(_ p: CGPoint) -> CGFloat {
        let g = geometry
        return atan2(p.x - g.cx, g.cy - p.y)
    }

    func setIndex(_ i: Int) {
        index = ((i % count) + count) % count
        angle = -CGFloat(index) * step
        setNeedsDisplay()
    }

    private func sync() {
        let raw = Int((-angle / step).rounded())
        let i = ((raw % count) + count) % count
        if i != index {
            index = i
            selection.selectionChanged()
            let now = CACurrentMediaTime()
            if soundEnabled && now - lastTick > 0.03 {
                AudioServicesPlaySystemSound(1104)
                lastTick = now
            }
            onPick?(i)
        }
        setNeedsDisplay()
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            stopLink()
            isInteracting = true
            selection.prepare()
            lastAngle = angleAt(p)
            lastTime = CACurrentMediaTime()
            velocity = 0
        case .changed:
            let a = angleAt(p)
            let da = wrapPi(a - lastAngle) * 1.15
            let now = CACurrentMediaTime()
            let dt = max(0.001, now - lastTime)
            lastAngle = a
            lastTime = now
            angle += da
            velocity = velocity * 0.6 + (da / CGFloat(dt)) * 0.4
            sync()
        default:
            if CACurrentMediaTime() - lastTime > 0.08 { velocity = 0 }
            coasting = true
            startLink()
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let a = angleAt(g.location(in: self))
        go(to: Int(((a - angle) / step).rounded()))
    }

    func go(to i: Int) {
        isInteracting = true
        let target = angle - wrapPi(CGFloat(i) * step + angle)
        beginTween(to: target)
    }

    private func beginTween(to target: CGFloat) {
        coasting = false
        tweenFrom = angle
        tweenTo = target
        tweenStart = CACurrentMediaTime()
        tweenDuration = min(0.52, 0.16 + Double(abs(target - angle)) * 0.9)
        startLink()
    }

    private func startLink() {
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        lastTime = CACurrentMediaTime()
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        if coasting {
            let dt = min(0.04, now - lastTime)
            lastTime = now
            if abs(velocity) > 0.4 {
                angle += velocity * CGFloat(dt)
                velocity *= CGFloat(pow(0.94, dt * 60))
                sync()
            } else {
                beginTween(to: -(-angle / step).rounded() * step)
            }
            return
        }
        let k = tweenDuration <= 0 ? 1 : min(1, (now - tweenStart) / tweenDuration)
        let e = 1 - pow(1 - k, 3)
        angle = tweenFrom + (tweenTo - tweenFrom) * CGFloat(e)
        sync()
        if k >= 1 {
            stopLink()
            isInteracting = false
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = bounds.width
        let h = bounds.height
        let g = geometry
        let r = g.r
        let cx = g.cx
        let cy = g.cy
        let vis = asin(min(1, (w / 2 + 24) / r))
        func point(_ a: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: cx + sin(a) * radius, y: cy - cos(a) * radius)
        }

        // Body with a soft shadow.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16, color: UIColor.black.withAlphaComponent(0.7).cgColor)
        UIColor(hex: 0x24201C).setFill()
        UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        ctx.restoreGState()

        // Knurled rim.
        let k = 320
        ctx.setLineWidth(1.1)
        for i in 0..<k {
            let a = wrapPi(CGFloat(i) * .pi * 2 / CGFloat(k) + angle)
            if abs(a) > vis { continue }
            let light = 0.5 + 0.5 * cos(a * 2.2 + 0.7)
            let c = i % 2 == 1 ? UIColor(red: 0.88, green: 0.85, blue: 0.79, alpha: 0.16 + light * 0.3) : UIColor.black.withAlphaComponent(0.6)
            ctx.setStrokeColor(c.cgColor)
            ctx.move(to: point(a, r - 1.5))
            ctx.addLine(to: point(a, r - 12))
            ctx.strokePath()
        }

        // Face and brushed rings.
        UIColor(hex: 0x1A1714).setFill()
        let face = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r - 13, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        face.fill()
        UIColor.white.withAlphaComponent(0.09).setStroke()
        face.lineWidth = 1
        face.stroke()
        var j = 0
        var ring = r - 17
        while ring > r - 110 {
            let path = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: ring,
                                    startAngle: -.pi / 2 - vis, endAngle: -.pi / 2 + vis, clockwise: true)
            UIColor.white.withAlphaComponent(0.008 + CGFloat(j * 7 % 5) * 0.004).setStroke()
            path.lineWidth = 1
            path.stroke()
            ring -= 2.5
            j += 1
        }

        // Engraved film names.
        let labelRadius = r - 33
        for i in 0..<count {
            let a = wrapPi(CGFloat(i) * step + angle)
            if abs(a) > vis { continue }
            let f = FilmStock.all[i]
            let selected = i == index
            let fade = 1 - pow(min(1, abs(a) / vis), 2)
            let font = UIFont.systemFont(ofSize: selected ? 15 : 13, weight: selected ? .bold : .semibold, width: .condensed)
            let color = selected ? UIColor(hex: 0xF2A63B) : UIColor(red: 0.89, green: 0.87, blue: 0.82, alpha: 0.3 + 0.62 * fade)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let label = f.dial as NSString
            let size = label.size(withAttributes: attrs)
            let p = point(a, labelRadius)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: a)
            label.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)
            UIColor(hex: f.color, alpha: selected ? 1 : 0.3 + 0.55 * fade).setFill()
            UIBezierPath(ovalIn: CGRect(x: -2.3, y: 10.7, width: 4.6, height: 4.6)).fill()
            ctx.restoreGState()
            let dot = point(a + step / 2, r - 20)
            UIColor(red: 0.89, green: 0.87, blue: 0.82, alpha: 0.35).setFill()
            UIBezierPath(ovalIn: CGRect(x: dot.x - 1.1, y: dot.y - 1.1, width: 2.2, height: 2.2)).fill()
        }

        // Brand ring.
        let brandRadius = r - 66
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .semibold, width: .condensed),
            .foregroundColor: UIColor(hex: 0x988F82, alpha: 0.9),
            .kern: 1.2,
        ]
        for group in FilmStock.brandGroups {
            let mid = wrapPi(CGFloat(group.start + group.end) / 2 * step + angle)
            if abs(mid) < vis {
                let label = group.brand as NSString
                let size = label.size(withAttributes: brandAttrs)
                let p = point(mid, brandRadius)
                ctx.saveGState()
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: mid)
                label.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: brandAttrs)
                ctx.restoreGState()
            }
            let edge = wrapPi((CGFloat(group.start) - 0.5) * step + angle)
            if abs(edge) < vis {
                ctx.setStrokeColor(UIColor(hex: 0x988F82, alpha: 0.5).cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: point(edge, brandRadius - 9))
                ctx.addLine(to: point(edge, brandRadius + 9))
                ctx.strokePath()
            }
        }

        // Index mark.
        UIColor(hex: 0xF2A63B).setFill()
        let marker = UIBezierPath()
        marker.move(to: CGPoint(x: cx - 6.5, y: 7))
        marker.addLine(to: CGPoint(x: cx + 6.5, y: 7))
        marker.addLine(to: CGPoint(x: cx, y: 17))
        marker.close()
        marker.fill()
        UIRectFill(CGRect(x: cx - 0.75, y: 17, width: 1.5, height: 13))

        let small: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold, width: .condensed),
            .foregroundColor: UIColor(hex: 0x988F82, alpha: 0.8),
            .kern: 1,
        ]
        ("FILM SIMULATION" as NSString).draw(at: CGPoint(x: 12, y: 6), withAttributes: small)
        let counter = String(format: "%02d / %d", index + 1, count) as NSString
        let cs = counter.size(withAttributes: small)
        counter.draw(at: CGPoint(x: w - 12 - cs.width, y: 6), withAttributes: small)

        // Fade the dial into the deck at both sides.
        let fadeW = min(56, w * 0.14)
        let deck = UIColor(hex: 0x181513)
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [deck.cgColor, deck.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 18, width: fadeW, height: h))
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: fadeW, y: 0), options: [])
            ctx.restoreGState()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: w - fadeW, y: 18, width: fadeW, height: h))
            ctx.drawLinearGradient(grad, start: CGPoint(x: w, y: 0), end: CGPoint(x: w - fadeW, y: 0), options: [])
            ctx.restoreGState()
        }
    }
}

struct DialView: UIViewRepresentable {
    let index: Int
    let soundEnabled: Bool
    let onPick: (Int) -> Void

    func makeUIView(context: Context) -> DialUIView {
        let v = DialUIView()
        v.onPick = onPick
        v.soundEnabled = soundEnabled
        v.setIndex(index)
        return v
    }

    func updateUIView(_ v: DialUIView, context: Context) {
        v.onPick = onPick
        v.soundEnabled = soundEnabled
        if v.index != index && !v.isInteracting {
            v.setIndex(index)
        }
        v.setNeedsDisplay()
    }
}
