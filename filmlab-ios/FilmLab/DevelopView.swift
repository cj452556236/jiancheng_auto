import SwiftUI

/// Exposure under the enlarger, then the print appears in the developer tray under a safelight.
@MainActor
struct DevelopView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var phase = 0            // 0 expose, 1 develop, 2 stop, 3 fix, 4 lights on
    @State var clock = "00:00"
    @State var emerged = false
    @State var rocking = false

    private var stepName: String {
        switch phase {
        case 0: return "曝光中"
        case 1: return "显影"
        case 2: return "停显"
        case 3: return "定影"
        default: return "水洗完成"
        }
    }

    var body: some View {
        let job = model.develop
        let safe = phase < 4
        ZStack {
            (safe ? Color(hex: 0x1B0403) : Color(hex: 0x151110))
                .ignoresSafeArea()
            if safe {
                RadialGradient(colors: [Color(hex: 0x4B0C05), Color(hex: 0x1B0403, opacity: 0)],
                               center: .top, startRadius: 0, endRadius: 520)
                    .ignoresSafeArea()
            }

            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(clock)
                        .font(.system(size: 26, design: .monospaced))
                        .foregroundStyle(Theme.led)
                        .shadow(color: Theme.led.opacity(0.55), radius: 6)
                    Text(stepName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xD9A08F))
                        .frame(minWidth: 70, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(hex: 0x060404), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x2B1714), lineWidth: 1))

                tray(job)

                Text(job?.info ?? " ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if job?.failed == true {
                    Text("冲印失败了，请返回再试一次。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.body)
                    Button("返回") { model.develop = nil }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.amber)
                } else if phase >= 4 {
                    HStack(spacing: 10) {
                        Button {
                            model.saveDeveloped()
                        } label: {
                            Text(job?.saved == true ? "已存入相册" : "存入相册")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x1B1206))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(job?.saved == true)
                        if let url = job?.fileURL {
                            ShareLink(item: url) {
                                Text("分享")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.metal)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(Theme.deck2, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                        Button {
                            model.develop = nil
                        } label: {
                            Text("继续调整")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.metal)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Theme.deck2, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(phase >= 4 ? "也可以长按照片存入相册" : "轻点任意处跳过显影")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.metal.opacity(0.55))
            }
            .padding(16)

            if let toast = model.toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.metal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(hex: 0x181513, opacity: 0.96), in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding(.top, 12)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: phase)
        .contentShape(Rectangle())
        .onTapGesture {
            if phase < 4 && job?.image != nil { finish() }
        }
        .task { await runSequence() }
    }

    @ViewBuilder
    private func tray(_ job: DevelopJob?) -> some View {
        let safe = phase < 4
        let aspect: CGFloat = {
            if let img = job?.image, img.size.height > 0 { return img.size.width / img.size.height }
            return 1
        }()
        ZStack {
            Color(hex: 0xF3EFE7)
            if let img = job?.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(emerged ? 1 : 0)
                    .brightness(emerged ? 0 : 0.5)
                    .contextMenu {
                        Button {
                            model.saveDeveloped()
                        } label: {
                            Label("存入相册", systemImage: "square.and.arrow.down")
                        }
                    }
            }
            Color(hex: 0xFF2A12)
                .blendMode(.multiply)
                .opacity(safe ? 1 : 0)
                .allowsHitTesting(false)
            if phase == 0 {
                RadialGradient(colors: [Color(hex: 0xFFFAEB, opacity: 0.95), Color(hex: 0xFFF5DC, opacity: 0)],
                               center: .center, startRadius: 0, endRadius: 260)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: 520, maxHeight: 460)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: 0x2A2724), Color(hex: 0x121010)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 18)
        )
        .rotationEffect(.degrees(safe && !reduceMotion ? (rocking ? 0.5 : -0.5) : 0))
        .animation(safe && !reduceMotion ? Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : Animation.default, value: rocking)
    }

    private func finish() {
        phase = 4
        emerged = true
        clock = "01:30"
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func runSequence() async {
        let seconds = model.develop?.seconds ?? 12
        clock = formatTime(seconds)
        rocking = true
        // Wait for the full-resolution render.
        var waited = 0.0
        while model.develop?.image == nil && model.develop?.failed != true && waited < 60 {
            await sleep(0.05)
            waited += 0.05
        }
        if model.develop?.failed == true || phase >= 4 { return }
        if reduceMotion {
            finish()
            return
        }
        // Enlarger exposure counts down the set time, quickly.
        let steps = 14
        for i in 0...steps {
            if phase >= 4 { return }
            clock = formatTime(max(0, seconds * Float(steps - i) / Float(steps)))
            await sleep(0.05)
        }
        if phase >= 4 { return }
        phase = 1
        withAnimation(.easeIn(duration: 2.4)) { emerged = true }
        for i in 0...52 {
            if phase >= 4 { return }
            let s = Int(Double(i) / 52 * 90)
            clock = String(format: "%02d:%02d", s / 60, s % 60)
            await sleep(0.05)
        }
        if phase >= 4 { return }
        phase = 2
        await sleep(0.4)
        if phase >= 4 { return }
        phase = 3
        await sleep(0.6)
        if phase >= 4 { return }
        finish()
    }
}

struct RingAroundView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("色环对照").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.metal)
                Spacer()
                Button("关闭") { dismiss() }.foregroundStyle(Theme.amber)
            }
            Text("暗房里调色靠环形色卡：九张样片各差一点滤光或曝光。挑一张看起来最自然的，点它就会套用到放大机上。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(model.ringTiles) { tile in
                        Button {
                            model.applyRing(tile)
                        } label: {
                            VStack(spacing: 4) {
                                Image(uiImage: tile.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(tile.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(tile.isCurrent ? Theme.amber : Theme.body)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(4)
                            .background(Color(hex: 0x0C0A09), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tile.isCurrent ? Theme.amber : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.deck.ignoresSafeArea())
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xCFC8BC))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("FilmLab 使用说明").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.metal)
                    Spacer()
                    Button("完成") { dismiss() }.foregroundStyle(Theme.amber)
                }
                section("拍一张胶片照片", [
                    "1. 点「相机」实时取景，画面里看到的就是胶片效果；轻点画面对焦。也可以点「相册」选照片。",
                    "2. 在「胶片」页转动转盘，28 种胶片随转随看。",
                    "3. 「暗房」像彩色放大机一样调色，「效果」加颗粒、光晕、漏光，「相框」套上底片边。",
                    "4. 按中间的按钮拍摄或冲印，看照片在显影盘里浮现，然后存入相册。",
                ])
                section("彩色暗房小知识", [
                    "负片放大（RA-4）：照片偏什么色就加什么色的滤镜。偏黄加 Y，偏品红加 M。曝光时间越长，照片越暗。",
                    "正片直接放大（Ilfochrome）规律相反：偏黄就减 Y，曝光越久越亮。",
                    "黑白多级相纸：反差等级 00 最柔、5 最硬，可以做硒调、棕调、金调和蓝晒调色。",
                    "试条：一次在画面上比较五档曝光时间，点中最好的一档。色环：九宫格对照，挑最自然的一张。",
                    "旋钮上下或左右拖动调整，双击回到标准滤光。",
                ])
                section("说明", [
                    "胶片效果是对色彩风格的模拟，与各胶片厂商无关。",
                    "样张来源：NASA 与 SpaceX（公有领域），Rachel Michetti 与 Stefan van der Walt（CC0）。",
                ])
            }
            .padding(18)
        }
        .background(Theme.deck.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
