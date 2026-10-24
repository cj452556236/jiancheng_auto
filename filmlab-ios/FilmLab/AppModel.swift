import SwiftUI
import AVFoundation
import Metal
import MetalKit
import Photos

enum CaptureMode { case photo, live }

enum PanelTab: String, CaseIterable, Identifiable {
    case film, dark, fx, frame
    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: return "胶片"
        case .dark: return "暗房"
        case .fx: return "效果"
        case .frame: return "相框"
        }
    }

    var caption: String {
        switch self {
        case .film: return "FILM"
        case .dark: return "DARK"
        case .fx: return "FX"
        case .frame: return "FRAME"
        }
    }
}

/// A photo loaded into the enlarger: full-resolution and preview textures.
final class StillImage {
    let full: MTLTexture
    let preview: MTLTexture
    let seed: Float
    let seedInt: Int
    let frameNo: Int
    let date: Date
    let isSample: Bool
    let name: String

    init(full: MTLTexture, preview: MTLTexture, seedInt: Int, isSample: Bool, name: String) {
        self.full = full
        self.preview = preview
        self.seedInt = seedInt
        self.seed = Float(seedInt % 997) + 0.37
        self.frameNo = 1 + seedInt % 36
        self.date = Date()
        self.isSample = isSample
        self.name = name
    }
}

struct DevelopJob: Identifiable {
    let id = UUID()
    var seconds: Float
    var image: UIImage?
    var jpeg: Data?
    var fileURL: URL?
    var info = ""
    var failed = false
    var saved = false
}

struct RingTile: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
    let dark: DarkroomSettings
    let isCurrent: Bool
}

final class AppModel: ObservableObject {
    @Published var settings: FilmSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published var mode: CaptureMode = .photo
    @Published var tab: PanelTab = .film
    @Published var previewImage: UIImage?
    @Published var compare = false {
        didSet { if compare != oldValue { schedulePreview() } }
    }
    @Published var testStrip = false {
        didSet { if testStrip != oldValue { schedulePreview() } }
    }
    @Published var liveFrameSize = CGSize(width: 3, height: 4)
    @Published var develop: DevelopJob?
    @Published var toast: String?
    @Published var ringTiles: [RingTile] = []
    @Published var showRing = false
    @Published var showHelp = false
    @Published var sourceLabel = "样张"
    @Published var thumbnail: UIImage?
    @Published var isSample = true

    let renderer: FilmRenderer?
    let camera = CameraController()
    private(set) var still: StillImage?
    private var previewLayout: FrameLayout?
    private let renderQueue = DispatchQueue(label: "filmlab.render", qos: .userInitiated)
    private var renderInFlight = false
    private var renderPending = false
    private var sampleIndex = 0
    private var liveSeed: Float = 0
    private var facing: AVCaptureDevice.Position = .back
    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var leakSeedApplied = -1

    static let samples: [(asset: String, name: String)] = [
        ("SamplePortrait", "宇航员肖像"), ("SampleDusk", "黄昏发射台"), ("SampleEspresso", "意式浓缩"), ("SampleCat", "猫"),
    ]

    init() {
        settings = FilmSettings.load()
        renderer = FilmRenderer()
        renderer?.setLeak(seed: settings.leakSeed)
        leakSeedApplied = settings.leakSeed
        camera.onFrameSize = { [weak self] size in
            self?.liveFrameSize = size
        }
        loadSample(0)
    }

    var film: FilmStock { settings.film }

    // MARK: Settings

    private func settingsChanged(from old: FilmSettings) {
        guard settings != old else { return }
        if settings.leakSeed != leakSeedApplied {
            leakSeedApplied = settings.leakSeed
            renderer?.setLeak(seed: settings.leakSeed)
        }
        saveWork?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { snapshot.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        schedulePreview()
    }

    func selectFilm(_ index: Int) {
        guard index != settings.filmIndex, FilmStock.all.indices.contains(index) else { return }
        var s = settings
        let previousFamily = s.film.family
        s.filmIndex = index
        s.grain = nil
        s.grainSize = nil
        s.halation = nil
        s.vignette = nil
        if s.film.family != previousFamily || s.dark.family != s.film.family {
            let keepPaper = s.dark.paper
            s.dark = .neutral(for: s.film.family)
            s.dark.paper = keepPaper
            if testStrip { testStrip = false }
        }
        settings = s
    }

    func resetEffects() {
        var s = settings
        s.ev = 0
        s.grain = nil
        s.grainSize = nil
        s.halation = nil
        s.vignette = nil
        s.bloom = 0
        s.leak = 0
        s.dust = 0
        settings = s
    }

    func shuffleLeak() {
        var s = settings
        s.leakSeed = (s.leakSeed + 1) % 9973
        if s.leak == 0 { s.leak = 0.6 }
        settings = s
    }

    func resetDarkroom() {
        let paper = settings.dark.paper
        settings.dark = .neutral(for: film.family)
        settings.dark.paper = paper
    }

    // MARK: Sources

    func loadSample(_ index: Int) {
        let count = AppModel.samples.count
        sampleIndex = ((index % count) + count) % count
        let sample = AppModel.samples[sampleIndex]
        guard let image = UIImage(named: sample.asset) else { return }
        loadImage(image, isSample: true, name: sample.name)
    }

    func nextSample() {
        loadSample(sampleIndex + 1)
    }

    func loadImage(_ image: UIImage, isSample: Bool, name: String, thenDevelop: Bool = false) {
        guard let renderer else { return }
        renderQueue.async {
            guard let full = ImageTools.upright(image, maxLong: 5000),
                  let small = ImageTools.downscale(full, maxLong: 1600),
                  let fullTexture = renderer.makeTexture(from: full),
                  let previewTexture = renderer.makeTexture(from: small) else {
                DispatchQueue.main.async { self.showToast("这张照片打不开，换一张试试") }
                return
            }
            let thumb = ImageTools.thumbnail(small, size: 120)
            let still = StillImage(full: fullTexture, preview: previewTexture, seedInt: Int.random(in: 0..<1_000_000),
                                   isSample: isSample, name: name)
            DispatchQueue.main.async {
                self.still = still
                self.isSample = isSample
                self.thumbnail = isSample ? nil : thumb.map { UIImage(cgImage: $0) }
                self.sourceLabel = isSample ? "样张 · \(name)" : "你的照片"
                self.testStrip = false
                self.schedulePreview()
                if thenDevelop { self.developCurrent() }
            }
        }
    }

    // MARK: Camera

    var liveDisplayAspect: CGFloat {
        let w = max(1, Int(liveFrameSize.width))
        let h = max(1, Int(liveFrameSize.height))
        let crop = Pipeline.crop(width: w, height: h, settings: settings)
        return CGFloat(crop.pixelWidth / max(crop.pixelHeight, 1))
    }

    func toggleCamera() {
        if mode == .live { stopLive() } else { startLive() }
    }

    func startLive() {
        CameraController.requestAccess { granted in
            guard granted else {
                self.showToast("没有相机权限：请到 设置 → FilmLab 打开相机")
                return
            }
            self.camera.start(position: self.facing) { ok in
                if ok {
                    self.testStrip = false
                    self.compare = false
                    self.mode = .live
                    self.sourceLabel = "实时取景"
                } else {
                    self.showToast("相机打不开，可以先从相册选照片")
                }
            }
        }
    }

    func stopLive() {
        guard mode == .live else { return }
        camera.stop()
        mode = .photo
        sourceLabel = still.map { $0.isSample ? "样张 · \($0.name)" : "你的照片" } ?? "样张"
        schedulePreview()
    }

    func flipCamera() {
        facing = facing == .back ? .front : .back
        camera.start(position: facing) { _ in }
    }

    func focus(at point: CGPoint) {
        camera.focus(at: point)
    }

    /// Called by the MTKView on the main thread for every display frame.
    func drawLive(in view: MTKView) {
        guard mode == .live, let renderer, let pixelBuffer = camera.latestPixelBuffer else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let crop = Pipeline.crop(width: w, height: h, settings: settings)
        liveSeed = (liveSeed + 17.3).truncatingRemainder(dividingBy: 1000)
        let size = view.drawableSize
        let u = Pipeline.uniforms(settings, crop: crop, width: Int(size.width), height: Int(size.height), seed: liveSeed)
        renderer.drawLive(in: view, pixelBuffer: pixelBuffer, uniforms: u)
    }

    // MARK: Rendering

    /// Renders the film look and wraps it in the chosen frame.
    private func renderComposite(still: StillImage, settings s: FilmSettings, full: Bool,
                                 compare: Bool, strip: Bool) -> (image: CGImage, layout: FrameLayout)? {
        guard let renderer else { return nil }
        let source = full ? still.full : still.preview
        let crop = Pipeline.crop(width: source.width, height: source.height, settings: s)
        var iw = Int(crop.pixelWidth.rounded())
        var ih = Int(crop.pixelHeight.rounded())
        let limit = full ? 6000.0 : 1400.0
        var layout = FrameLayout.make(s.frame, iw, ih)
        var scale = min(1.0, limit / Double(max(layout.W, layout.H)))
        if Double(layout.W * layout.H) * scale * scale > 16_500_000 {
            scale = sqrt(16_500_000 / Double(layout.W * layout.H))
        }
        if scale < 1 {
            iw = max(16, Int((Double(iw) * scale).rounded()))
            ih = max(16, Int((Double(ih) * scale).rounded()))
            layout = FrameLayout.make(s.frame, iw, ih)
        }
        let u = Pipeline.uniforms(s, crop: crop, width: iw, height: ih, seed: still.seed, bypass: compare, strip: strip)
        guard let rendered = renderer.renderImage(source: source, width: iw, height: ih, uniforms: u) else { return nil }
        let meta = FrameMeta(film: s.film, settings: s, date: still.date, frameNo: still.frameNo, seed: still.seedInt)
        guard let composed = Compositor.compose(image: rendered, layout: layout, meta: meta,
                                                stripTimes: strip ? s.stripTimes : nil) else { return nil }
        return (composed, layout)
    }

    func schedulePreview() {
        guard mode == .photo, let still else { return }
        if renderInFlight {
            renderPending = true
            return
        }
        renderInFlight = true
        let s = settings
        let compare = self.compare
        let strip = testStrip && !compare
        renderQueue.async {
            let result = self.renderComposite(still: still, settings: s, full: false, compare: compare, strip: strip)
            DispatchQueue.main.async {
                if let result {
                    self.previewImage = UIImage(cgImage: result.image)
                    self.previewLayout = result.layout
                }
                self.renderInFlight = false
                if self.renderPending {
                    self.renderPending = false
                    self.schedulePreview()
                }
            }
        }
    }

    /// `fraction` is the tap position across the preview image, 0...1.
    func pickStrip(atFraction fraction: CGFloat) {
        guard testStrip, let L = previewLayout else { return }
        let px = fraction * CGFloat(L.W)
        let band = min(4, max(0, Int((px - CGFloat(L.x)) / (CGFloat(L.w) / 5))))
        let t = settings.stripTimes[band]
        settings.dark.time = min(64, max(2, t < 10 ? (t * 10).rounded() / 10 : t.rounded()))
        testStrip = false
        showToast("曝光时间定为 \(formatTime(settings.dark.time))")
    }

    // MARK: Develop and save

    func shutter() {
        if mode == .live {
            camera.capture { image in
                guard let image else {
                    self.showToast("拍摄失败，再试一次")
                    return
                }
                self.stopLive()
                self.loadImage(image, isSample: false, name: "camera", thenDevelop: true)
            }
        } else {
            developCurrent()
        }
    }

    func developCurrent() {
        guard let still, develop == nil else { return }
        let s = settings
        let f = s.film
        develop = DevelopJob(seconds: s.dark.time)
        renderQueue.async {
            var image: UIImage?
            var jpeg: Data?
            var url: URL?
            var info = ""
            if let result = self.renderComposite(still: still, settings: s, full: true, compare: false, strip: false),
               let data = ImageTools.jpegData(result.image, quality: 0.92) {
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(AppModel.fileName(for: f))
                try? data.write(to: fileURL)
                image = UIImage(cgImage: result.image)
                jpeg = data
                url = fileURL
                info = "\(f.name) · \(f.processCN) · \(result.image.width)×\(result.image.height)"
            }
            DispatchQueue.main.async {
                guard self.develop != nil else { return }
                self.develop?.image = image
                self.develop?.jpeg = jpeg
                self.develop?.fileURL = url
                self.develop?.info = info
                self.develop?.failed = image == nil
            }
        }
    }

    static func fileName(for film: FilmStock) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let name = film.name.filter { $0.isLetter || $0.isNumber }
        return "FilmLab_\(name)_\(f.string(from: Date())).jpg"
    }

    func saveDeveloped() {
        guard let data = develop?.jpeg else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.showToast("没有相册权限：请到 设置 → FilmLab → 照片 允许添加") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { ok, _ in
                DispatchQueue.main.async {
                    if ok { self.develop?.saved = true }
                    self.showToast(ok ? "已存入相册" : "保存失败，请再试一次")
                }
            })
        }
    }

    // MARK: Ring-around

    func openRing() {
        guard mode == .photo, let still, let renderer else {
            showToast("色环需要一张照片，先拍一张或从相册选")
            return
        }
        let s = settings
        let family = s.film.family
        let brighter: Float = family == .pos ? 1.41 : 1 / 1.41
        let y = family.cast("y")
        let m = family.cast("m")
        let c = family.cast("c")
        let variants: [(String, Float, Float, Float, Float, Bool)] = [
            ("Y+15 \(y.0)", 0, 0, 15, 1, false), ("M+15 \(m.0)", 0, 15, 0, 1, false), ("C+15 \(c.0)", 15, 0, 0, 1, false),
            ("曝光 更亮", 0, 0, 0, brighter, false), ("当前", 0, 0, 0, 1, true), ("曝光 更暗", 0, 0, 0, 1 / brighter, false),
            ("Y−15 \(y.1)", 0, 0, -15, 1, false), ("M−15 \(m.1)", 0, -15, 0, 1, false), ("C−15 \(c.1)", -15, 0, 0, 1, false),
        ]
        renderQueue.async {
            let source = still.preview
            let crop = Pipeline.crop(width: source.width, height: source.height, settings: s)
            let ar = crop.pixelWidth / crop.pixelHeight
            let tw = ar >= 1 ? 360 : Int(360 * ar)
            let th = ar >= 1 ? Int(360 / ar) : 360
            var tiles: [RingTile] = []
            for v in variants {
                var t = s
                t.dark.c = min(150, max(0, t.dark.c + v.1))
                t.dark.m = min(150, max(0, t.dark.m + v.2))
                t.dark.y = min(150, max(0, t.dark.y + v.3))
                t.dark.time = min(64, max(2, (t.dark.time * v.4 * 10).rounded() / 10))
                let u = Pipeline.uniforms(t, crop: crop, width: tw, height: th, seed: still.seed)
                if let img = renderer.renderImage(source: source, width: tw, height: th, uniforms: u) {
                    tiles.append(RingTile(label: v.0, image: UIImage(cgImage: img), dark: t.dark, isCurrent: v.5))
                }
            }
            DispatchQueue.main.async {
                self.ringTiles = tiles
                self.showRing = true
            }
        }
    }

    func applyRing(_ tile: RingTile) {
        settings.dark = tile.dark
        showRing = false
        if !tile.isCurrent { showToast("已套用：\(tile.label)") }
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}
