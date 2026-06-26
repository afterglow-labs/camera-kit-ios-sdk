//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import CoreImage
import QuartzCore
import SCSDKCameraKit
import UIKit

/// Streams CameraKit's processed video output frames to a WebSocket endpoint.
///
/// This is intentionally frame-oriented instead of file-oriented: it receives CameraKit's
/// post-lens CMSampleBuffer output and sends lightweight JPEG frames for browser preview.
public final class CameraKitWebSocketStreamOutput: NSObject, Output, OutputRequiringPixelBuffer {
    public weak var delegate: SCCameraKitOutputRequiringPixelBufferDelegate?

    public var currentlyRequiresPixelBuffer = false {
        didSet {
            guard oldValue != currentlyRequiresPixelBuffer else { return }
            delegate?.outputChangedRequirements(self)
        }
    }

    public private(set) var isStreaming = false

    private let url: URL
    private let requestHeaders: [String: String]
    private let targetFrameInterval: CFTimeInterval
    private let jpegQuality: CGFloat
    private let maxDimension: CGFloat
    private let session: URLSession
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let encodingQueue = DispatchQueue(label: "com.afterglowlabs.vibecheck.stream.encode", qos: .userInitiated)
    private let sendQueue = DispatchQueue(label: "com.afterglowlabs.vibecheck.stream.send")
    private let stateLock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var lastFrameTime: CFTimeInterval = 0
    private var encodingFrame = false

    public init(
        url: URL,
        requestHeaders: [String: String] = [:],
        framesPerSecond: Double = 8,
        jpegQuality: CGFloat = 0.58,
        maxDimension: CGFloat = 540
    ) {
        self.url = url
        self.requestHeaders = requestHeaders
        self.targetFrameInterval = 1 / max(1, framesPerSecond)
        self.jpegQuality = min(1, max(0.05, jpegQuality))
        self.maxDimension = max(160, maxDimension)
        self.session = URLSession(configuration: .default)
        super.init()
    }

    deinit {
        stopStreaming()
    }

    public func startStreaming() {
        stateLock.lock()
        guard !isStreaming else {
            stateLock.unlock()
            return
        }
        isStreaming = true
        var request = URLRequest(url: url)
        for (name, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let task = session.webSocketTask(with: request)
        self.task = task
        stateLock.unlock()

        currentlyRequiresPixelBuffer = true
        task.resume()
        sendHello()
    }

    public func stopStreaming() {
        stateLock.lock()
        let task = self.task
        self.task = nil
        isStreaming = false
        encodingFrame = false
        stateLock.unlock()

        currentlyRequiresPixelBuffer = false
        task?.cancel(with: .goingAway, reason: nil)
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputTexture texture: Texture) {
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        guard shouldEncodeFrame(), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frame = PixelBufferFrame(pixelBuffer: pixelBuffer)
        encodingQueue.async { [weak self] in
            defer {
                self?.finishEncodingFrame()
            }

            guard let self, self.isStreaming else { return }
            guard let data = self.jpegFrame(from: frame.pixelBuffer) else { return }
            self.send(frame: data)
        }
    }

    private func shouldEncodeFrame() -> Bool {
        let now = CACurrentMediaTime()

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isStreaming, task != nil, !encodingFrame else { return false }
        guard now - lastFrameTime >= targetFrameInterval else { return false }
        lastFrameTime = now
        encodingFrame = true
        return true
    }

    private func finishEncodingFrame() {
        stateLock.lock()
        encodingFrame = false
        stateLock.unlock()
    }

    private func jpegFrame(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        let outputImage: CIImage
        if scale < 1 {
            outputImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            outputImage = ciImage
        }

        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality)
    }

    private func sendHello() {
        let payload: [String: Any] = [
            "type": "publisher",
            "source": "vibe-check",
            "format": "jpeg",
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let string = String(data: data, encoding: .utf8)
        else { return }

        sendQueue.async { [weak self] in
            self?.task?.send(.string(string)) { _ in }
        }
    }

    private func send(frame: Data) {
        sendQueue.async { [weak self] in
            self?.task?.send(.data(frame)) { error in
                if error != nil {
                    self?.stopStreaming()
                }
            }
        }
    }
}

private struct PixelBufferFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}
