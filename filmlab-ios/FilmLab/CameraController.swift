import AVFoundation
import UIKit

/// Live video frames for the viewfinder plus full-resolution stills.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "filmlab.camera.session")
    private let videoQueue = DispatchQueue(label: "filmlab.camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private(set) var position: AVCaptureDevice.Position = .back

    private let bufferLock = NSLock()
    private var latest: CVPixelBuffer?
    private var lastSize = CGSize.zero
    private var photoCompletion: ((UIImage?) -> Void)?

    /// Called on the main queue when the frame size changes.
    var onFrameSize: ((CGSize) -> Void)?

    var latestPixelBuffer: CVPixelBuffer? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return latest
    }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start(position: AVCaptureDevice.Position, completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            let ok = self.configure(position: position)
            if ok && !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.bufferLock.lock()
            self.latest = nil
            self.bufferLock.unlock()
        }
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if !configured {
            session.sessionPreset = .photo
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput), session.canAddOutput(photoOutput) else { return false }
            session.addOutput(videoOutput)
            session.addOutput(photoOutput)
            configured = true
        }

        if let current = input {
            session.removeInput(current)
            input = nil
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(newInput) else { return false }
        session.addInput(newInput)
        input = newInput
        self.position = position

        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            guard let connection else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
        return true
    }

    // MARK: Video frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latest = pixelBuffer
        bufferLock.unlock()
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        if size != lastSize {
            lastSize = size
            let callback = onFrameSize
            DispatchQueue.main.async { callback?(size) }
        }
    }

    // MARK: Stills

    func capture(_ completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.photoCompletion = completion
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        }
        let done = photoCompletion
        photoCompletion = nil
        DispatchQueue.main.async { done?(image) }
    }

    /// `point` is normalised to the portrait viewfinder (0...1, top-left origin).
    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.input?.device else { return }
            let p = self.position == .front ? CGPoint(x: point.y, y: point.x) : CGPoint(x: point.y, y: 1 - point.x)
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = p
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = p
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Focus is best effort.
            }
        }
    }
}
