//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import CoreMedia
import CoreVideo
import SCSDKCameraKit
import VideoToolbox

/// Normalizes caller-supplied video frames to formats accepted by Camera Kit's Lens processor.
final class ExternalInputCompatibilityAdapter: NSObject, Input, InputDestination {
    weak var destination: InputDestination?

    var horizontalFieldOfView: CGFloat { source.horizontalFieldOfView }
    var frameSize: CGSize { source.frameSize }
    var frameOrientation: AVCaptureVideoOrientation { source.frameOrientation }
    var position: AVCaptureDevice.Position {
        get { source.position }
        set { source.position = newValue }
    }
    var isRunning: Bool { source.isRunning }

    private let source: Input
    private let videoFrameConverter = ExternalInputVideoFrameConverter()

    init(source: Input) {
        self.source = source
        super.init()
        source.destination = self
    }

    func startRunning() {
        source.destination = self
        source.startRunning()
    }

    func stopRunning() {
        source.stopRunning()
    }

    func setVideoOrientation(_ videoOrientation: AVCaptureVideoOrientation) {
        source.setVideoOrientation(videoOrientation)
    }

    func inputChangedAttributes(_ input: Input) {
        destination?.inputChangedAttributes(self)
    }

    func input(_ input: Input, receivedVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        guard let compatibleSampleBuffer = videoFrameConverter.cameraKitCompatibleSampleBuffer(sampleBuffer) else {
            print("[CameraKit] Dropped an external video frame that could not be normalized")
            return
        }
        destination?.input(self, receivedVideoSampleBuffer: compatibleSampleBuffer)
    }

    func input(_ input: Input, receivedAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        destination?.input(self, receivedAudioSampleBuffer: sampleBuffer)
    }
}

/// Converts video-range NV12 to the full-range NV12 format consumed by LensCore.
final class ExternalInputVideoFrameConverter {
    private let lock = NSLock()
    private var transferSession: VTPixelTransferSession?
    private let outputPool = ExternalInputPixelBufferPool(
        pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    )

    deinit {
        if let transferSession {
            VTPixelTransferSessionInvalidate(transferSession)
        }
    }

    func cameraKitCompatibleSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        guard CVPixelBufferGetPixelFormatType(sourceBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return sampleBuffer
        }

        lock.lock()
        defer { lock.unlock() }
        return convert(sampleBuffer, sourceBuffer: sourceBuffer)
    }

    private func convert(_ sampleBuffer: CMSampleBuffer, sourceBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        guard width > 0, height > 0,
              let transferSession = makeTransferSessionIfNeeded(),
              let outputBuffer = outputPool.makeBuffer(width: width, height: height) else {
            return nil
        }

        guard VTPixelTransferSessionTransferImage(
            transferSession,
            from: sourceBuffer,
            to: outputBuffer
        ) == noErr else {
            return nil
        }

        return makeVideoSampleBuffer(source: sampleBuffer, imageBuffer: outputBuffer)
    }

    private func makeTransferSessionIfNeeded() -> VTPixelTransferSession? {
        if let transferSession {
            return transferSession
        }

        var newSession: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &newSession
        ) == noErr,
              let newSession else {
            return nil
        }
        transferSession = newSession
        return newSession
    }
}

private final class ExternalInputPixelBufferPool {
    private let pixelFormat: OSType
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0

    init(pixelFormat: OSType) {
        self.pixelFormat = pixelFormat
    }

    func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || self.width != width || self.height != height {
            pool = makePool(width: width, height: height)
            self.width = width
            self.height = height
        }
        guard let pool else { return nil }

        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &outputBuffer
        ) == kCVReturnSuccess else {
            return nil
        }
        return outputBuffer
    }

    private func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3,
        ]
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        ) == kCVReturnSuccess else {
            return nil
        }
        return pool
    }
}

private func makeVideoSampleBuffer(
    source sourceSampleBuffer: CMSampleBuffer,
    imageBuffer: CVPixelBuffer
) -> CMSampleBuffer? {
    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescriptionOut: &formatDescription
    ) == noErr,
    let formatDescription else {
        return nil
    }

    var timing = CMSampleTimingInfo()
    guard CMSampleBufferGetSampleTimingInfo(
        sourceSampleBuffer,
        at: 0,
        timingInfoOut: &timing
    ) == noErr else {
        return nil
    }

    var outputSampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &outputSampleBuffer
    ) == noErr,
    let outputSampleBuffer else {
        return nil
    }

    CMPropagateAttachments(sourceSampleBuffer, destination: outputSampleBuffer)
    return outputSampleBuffer
}
