import SwiftUI

/// A colour-head dial: drag up or right to turn it up, double-tap to return to neutral.
@MainActor
struct KnobView: View {
    let label: String
    let sub: String
    let tint: Color
    let range: ClosedRange<Float>
    var logarithmic = false
    var step: Float = 1
    var tickEvery: Float = 1
    let neutral: Float
    @Binding var value: Float
    let format: (Float) -> String

    @State var dragStart: Float? = nil

    private func toT(_ v: Float) -> Float {
        if logarithmic { return log(v / range.lowerBound) / log(range.upperBound / range.lowerBound) }
        return (v - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func fromT(_ t: Float) -> Float {
        if logarithmic { return range.lowerBound * pow(range.upperBound / range.lowerBound, t) }
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    private func snap(_ v: Float) -> Float {
        let c = min(range.upperBound, max(range.lowerBound, v))
        if logarithmic { return c < 10 ? (c * 10).rounded() / 10 : c.rounded() }
        return (c / step).rounded() * step
    }

    private func set(_ v: Float) {
        let n = snap(v)
        guard n != value else { return }
        if logarithmic || floor(n / tickEvery) != floor(value / tickEvery) { Haptics.tick() }
        value = n
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold).width(.condensed))
                    .tracking(1.4)
                    .foregroundStyle(Theme.metal)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
            Canvas { ctx, size in
                drawKnob(ctx, size)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = toT(value) }
                        let d = Float(g.translation.width - g.translation.height) / 200
                        set(fromT(min(1, max(0, (dragStart ?? 0) + d))))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = neutral
                Haptics.thump()
            })
            .accessibilityElement()
            .accessibilityLabel("\(label) \(sub)")
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(logarithmic ? value * 1.06 : value + step * 5)
                case .decrement: set(logarithmic ? value / 1.06 : value - step * 5)
                @unknown default: break
                }
            }
            Text(format(value))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.led)
                .shadow(color: Theme.led.opacity(0.55), radius: 4)
                .frame(minWidth: 50)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(Color(hex: 0x0B0908), in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(minWidth: 60)
    }

    private func drawKnob(_ ctx: GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height)
        let k = s / 58
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let a0 = -Double.pi * 0.75
        let a1 = Double.pi * 0.75
        func ang(_ t: Float) -> Double { a0 + (a1 - a0) * Double(t) }
        func pt(_ a: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: c.x + CGFloat(sin(a)) * r * k, y: c.y - CGFloat(cos(a)) * r * k)
        }

        for i in 0...20 {
            let a = ang(Float(i) / 20)
            var p = Path()
            p.move(to: pt(a, i % 5 == 0 ? 24.5 : 26))
            p.addLine(to: pt(a, 28))
            ctx.stroke(p, with: .color(i % 5 == 0 ? Theme.metal.opacity(0.75) : Theme.muted.opacity(0.45)), lineWidth: 1)
        }

        let tn = toT(neutral)
        let tv = toT(value)
        var arc = Path()
        arc.addArc(center: c, radius: 22.2 * k,
                   startAngle: .radians(min(ang(tn), ang(tv)) - .pi / 2),
                   endAngle: .radians(max(ang(tn), ang(tv)) - .pi / 2 + 0.001), clockwise: false)
        ctx.stroke(arc, with: .color(tint), lineWidth: 2.4)

        let bodyRect = CGRect(x: c.x - 19 * k, y: c.y - 19 * k, width: 38 * k, height: 38 * k)
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2))
        shadowed.fill(Path(ellipseIn: bodyRect),
                      with: .radialGradient(Gradient(colors: [Color(hex: 0x5A544D), Color(hex: 0x1B1815)]),
                                            center: CGPoint(x: c.x - 5 * k, y: c.y - 6 * k), startRadius: 2 * k, endRadius: 19 * k))

        for i in 0..<24 {
            let a = Double(i) / 24 * Double.pi * 2 + ang(tv)
            var p = Path()
            p.move(to: pt(a, 16.5))
            p.addLine(to: pt(a, 19))
            ctx.stroke(p, with: .color(.black.opacity(0.45)), lineWidth: 1)
        }

        let capRect = CGRect(x: c.x - 13.5 * k, y: c.y - 13.5 * k, width: 27 * k, height: 27 * k)
        ctx.fill(Path(ellipseIn: capRect),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x6A645C), Color(hex: 0x2A2622)]),
                                       center: CGPoint(x: c.x - 3 * k, y: c.y - 4 * k), startRadius: 1 * k, endRadius: 13 * k))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3 * k, y: c.y - 3 * k, width: 6 * k, height: 6 * k)), with: .color(tint))

        var needle = Path()
        needle.move(to: pt(ang(tv), 7))
        needle.addLine(to: pt(ang(tv), 17))
        ctx.stroke(needle, with: .color(Color(hex: 0xF3EEE5)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}
