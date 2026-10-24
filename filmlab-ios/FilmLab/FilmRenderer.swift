import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreGraphics

private struct BrightUniforms {
    var crop: SIMD4<Float>
    var params: SIMD4<Float>
}

private struct BlurUniforms {
    var dir: SIMD4<Float>
}

/// Runs the film pipeline on the GPU, either into an MTKView drawable (live camera)
/// or into an offscreen texture that is read back as a CGImage (stills and exports).
final class FilmRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let brightPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let finalPipeline: MTLRenderPipelineState
    private var blurTextures: [MTLTexture] = []
    private var blurWidth = 0
    private var blurHeight = 0
    private var leakTexture: MTLTexture
    private var dustTexture: MTLTexture
    private var textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    let maxTextureSize = 8192

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        func pipeline(_ fragment: String, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: d)
        }

        guard let bright = pipeline("brightFragment", .rgba16Float),
              let blur = pipeline("blurFragment", .rgba16Float),
              let finalPSO = pipeline("finalFragment", .bgra8Unorm),
              let blank1 = FilmRenderer.blankTexture(device),
              let blank2 = FilmRenderer.blankTexture(device) else { return nil }

        self.device = device
        self.queue = queue
        self.brightPipeline = bright
        self.blurPipeline = blur
        self.finalPipeline = finalPSO
        self.leakTexture = blank1
        self.dustTexture = blank2
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        if let dust = Plates.dust(), let tex = makeTexture(from: dust) {
            dustTexture = tex
        }
    }

    private static func blankTexture(_ device: MTLDevice) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        var black: [UInt8] = [0, 0, 0, 255]
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        return t
    }

    func setLeak(seed: Int) {
        guard let plate = Plates.leak(seed: seed), let tex = makeTexture(from: plate) else { return }
        lock.lock()
        leakTexture = tex
        lock.unlock()
    }

    /// Uploads an image as raw sRGB-encoded RGBA8, top row first.
    func makeTexture(from image: CGImage) -> MTLTexture? {
        let w = image.width
        let h = image.height
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: d),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = w * 4
        var data = Data(count: bytesPerRow * h)
        let ok: Bool = data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
            return true
        }
        return ok ? tex : nil
    }

    private func ensureBlurTextures(_ w: Int, _ h: Int) {
        if w == blurWidth && h == blurHeight && blurTextures.count == 3 { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        blurTextures = (0..<3).compactMap { _ in device.makeTexture(descriptor: d) }
        blurWidth = w
        blurHeight = h
    }

    private func pass(_ cb: MTLCommandBuffer, target: MTLTexture, pipeline: MTLRenderPipelineState,
                      setup: (MTLRenderCommandEncoder) -> Void) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipeline)
        setup(enc)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func blur(_ cb: MTLCommandBuffer, from: MTLTexture, to: MTLTexture, dx: Float, dy: Float) {
        var u = BlurUniforms(dir: SIMD4<Float>(dx / Float(blurWidth), dy / Float(blurHeight), 0, 0))
        pass(cb, target: to, pipeline: blurPipeline) { enc in
            enc.setFragmentTexture(from, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<BlurUniforms>.stride, index: 0)
        }
    }

    /// Encodes the whole pipeline. Caller holds the lock.
    private func encode(_ cb: MTLCommandBuffer, source: MTLTexture, target: MTLTexture, uniforms: FilmUniforms) {
        let ow = target.width
        let oh = target.height
        let bw = ow >= oh ? 512 : max(8, Int((512.0 * Double(ow) / Double(oh)).rounded()))
        let bh = ow >= oh ? max(8, Int((512.0 * Double(oh) / Double(ow)).rounded())) : 512
        ensureBlurTextures(bw, bh)
        guard blurTextures.count == 3 else { return }
        let a = blurTextures[0]
        let b = blurTextures[1]
        let c = blurTextures[2]
        var u = uniforms
        u.res.x = Float(ow)
        u.res.y = Float(oh)

        if u.res.w < 0.5 {
            var bu = BrightUniforms(crop: u.crop,
                                    params: SIMD4<Float>(abs(u.crop.z) / Float(bw) * 0.25, abs(u.crop.w) / Float(bh) * 0.25, u.fx3.z, 0))
            pass(cb, target: a, pipeline: brightPipeline) { enc in
                enc.setFragmentTexture(source, index: 0)
                enc.setFragmentBytes(&bu, length: MemoryLayout<BrightUniforms>.stride, index: 0)
            }
            blur(cb, from: a, to: b, dx: 1.3, dy: 0)
            blur(cb, from: b, to: a, dx: 0, dy: 1.3)
            blur(cb, from: a, to: b, dx: 1.6, dy: 0)
            blur(cb, from: b, to: a, dx: 0, dy: 1.6)
            blur(cb, from: a, to: b, dx: 3.5, dy: 0)
            blur(cb, from: b, to: c, dx: 0, dy: 3.5)
            blur(cb, from: c, to: b, dx: 6, dy: 0)
            blur(cb, from: b, to: c, dx: 0, dy: 6)
        }

        let leak = leakTexture
        let dust = dustTexture
        pass(cb, target: target, pipeline: finalPipeline) { enc in
            enc.setFragmentTexture(source, index: 0)
            enc.setFragmentTexture(a, index: 1)
            enc.setFragmentTexture(c, index: 2)
            enc.setFragmentTexture(leak, index: 3)
            enc.setFragmentTexture(dust, index: 4)
            enc.setFragmentBytes(&u, length: MemoryLayout<FilmUniforms>.stride, index: 0)
        }
    }

    /// Renders offscreen and returns the result as an sRGB CGImage.
    func renderImage(source: MTLTexture, width: Int, height: Int, uniforms: FilmUniforms) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d) else { return nil }

        lock.lock()
        guard let cb = queue.makeCommandBuffer() else { lock.unlock(); return nil }
        encode(cb, source: source, target: target, uniforms: uniforms)
        cb.commit()
        lock.unlock()
        cb.waitUntilCompleted()

        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            if let base = raw.baseAddress {
                target.getBytes(base, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// Renders one camera frame straight into the view's drawable.
    func drawLive(in view: MTKView, pixelBuffer: CVPixelBuffer, uniforms: FilmUniforms) {
        guard let cache = textureCache, let drawable = view.currentDrawable else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, w, h, 0, &cvTexture)
        guard let cvTexture, let source = CVMetalTextureGetTexture(cvTexture) else { return }

        lock.lock()
        guard let cb = queue.makeCommandBuffer() else { lock.unlock(); return }
        encode(cb, source: source, target: drawable.texture, uniforms: uniforms)
        lock.unlock()
        cb.addCompletedHandler { _ in
            _ = cvTexture
        }
        cb.present(drawable)
        cb.commit()
    }
}
