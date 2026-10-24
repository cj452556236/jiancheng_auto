import SwiftUI
import PhotosUI
import MetalKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 8) {
                TopBar()
                ViewfinderView()
                    .frame(maxHeight: .infinity)
                TabBar()
                PanelContainer()
                    .frame(height: 214)
                ShutterRow(pickerItem: $pickerItem)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)

            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.metal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(hex: 0x181513, opacity: 0.96), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    .padding(.top, 64)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .fullScreenCover(item: $model.develop) { _ in
            DevelopView().environmentObject(model)
        }
        .sheet(isPresented: $model.showRing) {
            RingAroundView().environmentObject(model)
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, let image = UIImage(data: data) {
                        model.stopLive()
                        model.loadImage(image, isSample: false, name: "photo")
                        model.showToast("照片已装片，转动转盘挑胶片")
                    } else {
                        model.showToast("这张照片打不开，换一张试试")
                    }
                    pickerItem = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stopLive() }
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let film = model.film
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("FILM").foregroundStyle(Theme.metal)
                    Text("LAB").foregroundStyle(Theme.amber)
                }
                .font(.system(size: 20, weight: .bold).width(.condensed))
                .tracking(3)
                Text("胶片暗房")
                    .font(.system(size: 10))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button {
                model.tab = .film
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: film.color))
                        .frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.28), lineWidth: 1))
                    Text(film.name.uppercased())
                        .font(.system(size: 15, weight: .semibold).width(.condensed))
                        .tracking(0.8)
                        .lineLimit(1)
                        .foregroundStyle(Theme.metal)
                    Text("\(film.process) · \(film.iso)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(Theme.deck, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                model.settings.sound.toggle()
            } label: {
                Image(systemName: model.settings.sound ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(model.settings.sound ? "关闭转盘声音" : "打开转盘声音")
            Button {
                model.showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("使用说明")
        }
        .frame(minHeight: 40)
    }
}

// MARK: - Viewfinder

struct LiveMetalView: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: model.renderer?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.03, green: 0.027, blue: 0.024, alpha: 1)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator: NSObject, MTKViewDelegate {
        let model: AppModel
        init(model: AppModel) { self.model = model }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) { model.drawLive(in: view) }
    }
}

struct ViewfinderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.viewfinder)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x2A2622), lineWidth: 1))

            Group {
                if model.mode == .live && model.renderer != nil {
                    LiveMetalView(model: model)
                        .aspectRatio(model.liveDisplayAspect, contentMode: .fit)
                        .overlay(
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { v in
                                        model.focus(at: CGPoint(x: v.location.x / max(geo.size.width, 1),
                                                                y: v.location.y / max(geo.size.height, 1)))
                                    })
                            }
                        )
                } else if let image = model.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
                        .overlay(
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { _ in
                                                if !model.testStrip && !model.compare { model.compare = true }
                                            }
                                            .onEnded { v in
                                                if model.testStrip {
                                                    model.pickStrip(atFraction: v.location.x / max(geo.size.width, 1))
                                                } else {
                                                    model.compare = false
                                                }
                                            }
                                    )
                            }
                        )
                } else if model.renderer == nil {
                    Text("这台设备不支持 Metal，FilmLab 无法显影。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.body)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView().tint(Theme.muted)
                }
            }
            .padding(12)

            VStack {
                HStack(spacing: 6) {
                    Text(model.sourceLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                    if model.mode == .photo && model.isSample {
                        Button("换一张样张") { model.nextSample() }
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.metal)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                    }
                    Spacer()
                    if model.mode == .live {
                        Button {
                            model.flipCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.metal)
                                .padding(8)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        .accessibilityLabel("切换前后镜头")
                    }
                }
                Spacer()
                HStack {
                    Text(model.mode == .live ? "轻点画面对焦" : (model.testStrip ? "点一档试条选定曝光时间" : "按住画面查看原图"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.metal.opacity(0.75))
                        .shadow(color: .black, radius: 3)
                    Spacer()
                    if model.mode == .live {
                        Text("● LIVE")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.led)
                    }
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(minHeight: 170)
    }
}

// MARK: - Tabs and panels

struct TabBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                let selected = model.tab == tab
                Button {
                    model.tab = tab
                    if tab != .dark && model.testStrip { model.testStrip = false }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title).font(.system(size: 13))
                        Text(tab.caption)
                            .font(.system(size: 10, weight: .semibold).width(.condensed))
                            .tracking(1.2)
                            .opacity(0.65)
                    }
                    .foregroundStyle(selected ? Theme.metal : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(selected ? Theme.deck2 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .bottom) {
                        if selected {
                            Rectangle().fill(Theme.amber).frame(height: 2).padding(.horizontal, 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.deck, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}

struct PanelContainer: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.tab {
            case .film: FilmPanel()
            case .dark: DarkroomPanel()
            case .fx: EffectsPanel()
            case .frame: FramePanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deck, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FilmPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let film = model.film
        VStack(alignment: .leading, spacing: 0) {
            DialView(index: model.settings.filmIndex, soundEnabled: model.settings.sound) { i in
                model.selectFilm(i)
            }
            .frame(height: 132)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(film.name)
                        .font(.system(size: 18, weight: .bold).width(.condensed))
                        .foregroundStyle(Theme.metal)
                    Text("\(film.brandCN) · \(film.processCN) · ISO \(film.iso)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Text(film.desc)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0xBDB5A8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
    }
}

struct DarkroomPanel: View {
    @EnvironmentObject var model: AppModel

    private func binding(_ keyPath: WritableKeyPath<DarkroomSettings, Float>) -> Binding<Float> {
        Binding(get: { model.settings.dark[keyPath: keyPath] },
                set: { model.settings.dark[keyPath: keyPath] = $0 })
    }

    var body: some View {
        let family = model.film.family
        let neutral = DarkroomSpec.neutral(family)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(family.processTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.metal)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Pill(title: "试条", active: model.testStrip) {
                    model.testStrip.toggle()
                    if model.testStrip { model.showToast("画面分成五档曝光时间，点最满意的一档") }
                }
                if family != .bw {
                    Pill(title: "色环") { model.openRing() }
                }
                Pill(title: "复位") { model.resetDarkroom() }
            }
            Text(family.hint)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .top) {
                if family == .bw {
                    Spacer()
                    KnobView(label: "GRADE", sub: "反差", tint: Theme.metal, range: 0...6, step: 1, neutral: 3,
                             value: Binding(get: { Float(model.settings.dark.grade) },
                                            set: { model.settings.dark.grade = Int($0.rounded()) }),
                             format: { DarkroomSpec.grades[min(6, max(0, Int($0.rounded())))] })
                    Spacer()
                } else {
                    KnobView(label: "C", sub: "青", tint: Color(hex: 0x2FB8C9), range: 0...150, tickEvery: 5,
                             neutral: neutral.c, value: binding(\.c), format: { "\(Int($0))" })
                    Spacer(minLength: 0)
                    KnobView(label: "M", sub: "品", tint: Color(hex: 0xD0368A), range: 0...150, tickEvery: 5,
                             neutral: neutral.m, value: binding(\.m), format: { "\(Int($0))" })
                    Spacer(minLength: 0)
                    KnobView(label: "Y", sub: "黄", tint: Color(hex: 0xE8C21F), range: 0...150, tickEvery: 5,
                             neutral: neutral.y, value: binding(\.y), format: { "\(Int($0))" })
                    Spacer(minLength: 0)
                }
                KnobView(label: "TIME", sub: "曝光", tint: Theme.amber, range: 2...64, logarithmic: true,
                         neutral: neutral.time, value: binding(\.time), format: { formatTime($0) })
                if family == .bw { Spacer() }
            }
            .padding(.vertical, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if family == .bw {
                        PaneLabel(text: "调色")
                        ForEach(DarkroomSpec.tones.indices, id: \.self) { i in
                            Chip(title: DarkroomSpec.tones[i].name, selected: model.settings.dark.tone == i) {
                                model.settings.dark.tone = i
                            }
                        }
                    } else {
                        PaneLabel(text: "相纸")
                        ForEach(DarkroomSpec.papers.indices, id: \.self) { i in
                            Chip(title: DarkroomSpec.papers[i].name, selected: model.settings.dark.paper == i) {
                                model.settings.dark.paper = i
                            }
                        }
                    }
                    Rectangle().fill(Theme.line).frame(width: 1, height: 18).padding(.horizontal, 2)
                    PaneLabel(text: "表面")
                    let surfaces = family == .bw ? DarkroomSpec.surfacesBW : DarkroomSpec.surfaces
                    ForEach(surfaces.indices, id: \.self) { i in
                        Chip(title: surfaces[i].name, selected: model.settings.dark.surface == i) {
                            model.settings.dark.surface = i
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct EffectSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: (Float) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.body)
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.amber)
            }
            Slider(value: $value, in: range)
                .tint(Theme.amber)
                .controlSize(.mini)
        }
    }
}

struct EffectsPanel: View {
    @EnvironmentObject var model: AppModel

    private func percent(_ v: Float) -> String { "\(Int((v * 100).rounded()))" }

    var body: some View {
        let s = model.settings
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                EffectSlider(label: "曝光补偿", value: Binding(get: { s.ev }, set: { model.settings.ev = ($0 * 10).rounded() / 10 }),
                             range: -2...2, format: { String(format: "%+.1f EV", $0) })
                EffectSlider(label: "颗粒", value: Binding(get: { s.grainValue }, set: { model.settings.grain = $0 }),
                             range: 0...1, format: percent)
                EffectSlider(label: "颗粒大小", value: Binding(get: { s.grainSizeValue }, set: { model.settings.grainSize = $0 }),
                             range: 0.5...3, format: { String(format: "%.2f", $0) })
                EffectSlider(label: "红色光晕", value: Binding(get: { s.halationValue }, set: { model.settings.halation = $0 }),
                             range: 0...1, format: percent)
                EffectSlider(label: "柔焦 Pro-Mist", value: Binding(get: { s.bloom }, set: { model.settings.bloom = $0 }),
                             range: 0...1, format: percent)
                EffectSlider(label: "暗角", value: Binding(get: { s.vignetteValue }, set: { model.settings.vignette = $0 }),
                             range: 0...1, format: percent)
                EffectSlider(label: "漏光", value: Binding(get: { s.leak }, set: { model.settings.leak = $0 }),
                             range: 0...1, format: percent)
                EffectSlider(label: "灰尘划痕", value: Binding(get: { s.dust }, set: { model.settings.dust = $0 }),
                             range: 0...1, format: percent)
            }
            HStack(spacing: 6) {
                Pill(title: "日期戳 " + todayStamp, active: s.dateStamp) { model.settings.dateStamp.toggle() }
                Spacer()
                Pill(title: "换一种漏光") { model.shuffleLeak() }
                Pill(title: "恢复胶片默认") { model.resetEffects() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var todayStamp: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "'%02d %02d %02d", (c.year ?? 2026) % 100, c.month ?? 1, c.day ?? 1)
    }
}

struct FrameIcon: View {
    let kind: FrameKind

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / 54, size.height / 34)
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
            }
            let photo = Color(hex: 0x6D665C)
            switch kind {
            case .none:
                ctx.fill(Path(roundedRect: r(7, 5, 40, 24), cornerRadius: 1.5), with: .color(photo))
            case .film35:
                ctx.fill(Path(r(2, 3, 50, 28)), with: .color(Color(hex: 0x0D0B0A)))
                ctx.stroke(Path(r(2, 3, 50, 28)), with: .color(Color(hex: 0x4A443D)), lineWidth: 1)
                ctx.fill(Path(r(9, 9, 36, 16)), with: .color(photo))
                for x in stride(from: CGFloat(4), through: 46, by: 6) {
                    ctx.fill(Path(roundedRect: r(x, 4.5, 2.6, 2), cornerRadius: 0.5), with: .color(Color(hex: 0xD8D1C3)))
                    ctx.fill(Path(roundedRect: r(x, 27.5, 2.6, 2), cornerRadius: 0.5), with: .color(Color(hex: 0xD8D1C3)))
                }
            case .film120:
                ctx.fill(Path(r(8, 2, 38, 30)), with: .color(Color(hex: 0x0D0B0A)))
                ctx.stroke(Path(r(8, 2, 38, 30)), with: .color(Color(hex: 0x4A443D)), lineWidth: 1)
                ctx.fill(Path(r(13, 5, 28, 24)), with: .color(photo))
            case .slide:
                ctx.fill(Path(roundedRect: r(11, 1, 32, 32), cornerRadius: 3 * k), with: .color(Color(hex: 0xE7E3DA)))
                ctx.fill(Path(r(16, 10, 22, 14)), with: .color(photo))
            case .print:
                ctx.fill(Path(r(6, 2, 42, 30)), with: .color(Color(hex: 0xEFEBE3)))
                ctx.fill(Path(r(10, 5, 34, 20)), with: .color(Color(hex: 0x121110)))
                ctx.fill(Path(r(11, 6, 32, 18)), with: .color(photo))
            case .instant:
                ctx.fill(Path(r(14, 1, 26, 32)), with: .color(Color(hex: 0xEFEBE3)))
                ctx.fill(Path(r(16.5, 3.5, 21, 21)), with: .color(photo))
            }
        }
        .frame(width: 54, height: 34)
    }
}

struct FramePanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settings
        let fixed = s.frame.fixedAspect
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(FrameKind.allCases) { kind in
                    let selected = s.frame == kind
                    Button {
                        model.settings.frame = kind
                    } label: {
                        VStack(spacing: 4) {
                            FrameIcon(kind: kind)
                            Text(kind.title).font(.system(size: 11.5)).lineLimit(1)
                        }
                        .foregroundStyle(selected ? Theme.amber : Theme.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selected ? Theme.amber.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.amber : Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PaneLabel(text: fixed == nil ? "画幅" : (fixed == 1 ? "画幅 · 固定 1:1" : "画幅 · 固定 3:2"))
                    ForEach(AspectKind.allCases) { a in
                        Chip(title: a.title, selected: fixed == nil && s.aspect == a, disabled: fixed != nil) {
                            model.settings.aspect = a
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Shutter row

struct ShutterRow: View {
    @EnvironmentObject var model: AppModel
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        let live = model.mode == .live
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(.black)
                        if let thumb = model.thumbnail {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 19)).foregroundStyle(Theme.metal)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                    Text("相册").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从相册选择照片")

            Spacer()

            VStack(spacing: 5) {
                Button {
                    Haptics.thump()
                    model.shutter()
                } label: {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color(hex: 0x4A453F), Color(hex: 0x1C1916)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
                        Circle().stroke(Color(hex: 0x4F4840), lineWidth: 2).padding(-4)
                        Circle()
                            .fill(RadialGradient(colors: live
                                                 ? [.white, Color(hex: 0xE8E4DC), Color(hex: 0xA9A399)]
                                                 : [Color(hex: 0xFFD38A), Theme.amber, Color(hex: 0xB86C14)],
                                                 center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: 30))
                            .padding(10)
                    }
                    .frame(width: 68, height: 68)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(live ? "拍摄" : "冲印这张照片")
                Text(live ? "拍 摄" : "冲 印")
                    .font(.system(size: 11, weight: .semibold).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(Theme.metal)
            }

            Spacer()

            Button {
                model.toggleCamera()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: live ? "xmark" : "camera")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.metal)
                        .frame(width: 46, height: 46)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                    Text(live ? "关闭" : "相机").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(live ? "关闭相机" : "打开相机")
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 84)
    }
}
