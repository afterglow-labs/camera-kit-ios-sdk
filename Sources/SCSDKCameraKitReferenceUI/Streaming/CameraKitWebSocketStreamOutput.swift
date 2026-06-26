//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import CoreImage
import QuartzCore
import SCSDKCameraKit
import UIKit

/// Streams CameraKit's processed video output frames to a WebSocket endpoint.
///
/// This is intentionally frame-oriented instead of file-oriented: it receives CameraKit's
/// post-lens CMSampleBuffer output and sends JPEG video frames plus PCM audio packets for browser preview.
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
    private let audioQueue = DispatchQueue(label: "com.afterglowlabs.vibecheck.stream.audio", qos: .userInitiated)
    private let sendQueue = DispatchQueue(label: "com.afterglowlabs.vibecheck.stream.send")
    private let stateLock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var lastFrameTime: CFTimeInterval = 0
    private var encodingFrame = false
    private var audioSequence = 0

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
        guard isStreaming else { return }
        let audioSample = AudioSampleBuffer(sampleBuffer: sampleBuffer)
        audioQueue.async { [weak self] in
            guard let self, self.isStreaming else { return }
            guard let payload = self.pcmAudioPayload(from: audioSample.sampleBuffer) else { return }
            let sequence = self.audioSequence
            self.audioSequence += 1
            self.send(audio: payload, sequence: sequence)
        }
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

    private func pcmAudioPayload(from sampleBuffer: CMSampleBuffer) -> AudioPayload? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return nil }

        let audioFormat = streamDescription.pointee
        guard audioFormat.mFormatID == kAudioFormatLinearPCM else { return nil }

        let channelCount = Int(audioFormat.mChannelsPerFrame)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard channelCount > 0, frameCount > 0, audioFormat.mSampleRate > 0 else { return nil }

        var audioBufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &audioBufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard status == noErr, audioBufferListSize > 0 else { return nil }

        let rawAudioBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawAudioBufferList.deallocate() }

        let audioBufferList = rawAudioBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard !buffers.isEmpty else { return nil }

        let flags = audioFormat.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
        let isNonInterleaved = flags & kAudioFormatFlagIsNonInterleaved != 0
        let bitsPerChannel = Int(audioFormat.mBitsPerChannel)

        let pcmData: Data?
        if isFloat, bitsPerChannel == 32, !isBigEndian {
            pcmData = interleavedInt16DataFromFloat32(
                buffers: buffers,
                frameCount: frameCount,
                channelCount: channelCount,
                audioFormat: audioFormat,
                isNonInterleaved: isNonInterleaved
            )
        } else if isSignedInteger, bitsPerChannel == 16 {
            pcmData = interleavedInt16Data(
                buffers: buffers,
                frameCount: frameCount,
                channelCount: channelCount,
                audioFormat: audioFormat,
                isNonInterleaved: isNonInterleaved,
                isBigEndian: isBigEndian
            )
        } else {
            pcmData = nil
        }

        guard let pcmData, !pcmData.isEmpty else { return nil }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        return AudioPayload(
            data: pcmData,
            sampleRate: audioFormat.mSampleRate,
            channelCount: channelCount,
            frameCount: frameCount,
            presentationTimeSeconds: presentationTime.isValid ? presentationTime.seconds : nil
        )
    }

    private func interleavedInt16DataFromFloat32(
        buffers: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        channelCount: Int,
        audioFormat: AudioStreamBasicDescription,
        isNonInterleaved: Bool
    ) -> Data? {
        var data = Data()
        data.reserveCapacity(frameCount * channelCount * MemoryLayout<Int16>.size)

        if isNonInterleaved {
            guard buffers.count >= channelCount else { return nil }
            let stride = max(MemoryLayout<Float>.size, Int(audioFormat.mBytesPerFrame))
            for frameIndex in 0..<frameCount {
                for channelIndex in 0..<channelCount {
                    guard
                        let source = buffers[channelIndex].mData,
                        frameIndex * stride + MemoryLayout<Float>.size <= Int(buffers[channelIndex].mDataByteSize)
                    else { return nil }
                    let sample = source.load(fromByteOffset: frameIndex * stride, as: Float.self)
                    appendClampedInt16(sample, to: &data)
                }
            }
        } else {
            guard let source = buffers[0].mData else { return nil }
            let frameStride = max(channelCount * MemoryLayout<Float>.size, Int(audioFormat.mBytesPerFrame))
            for frameIndex in 0..<frameCount {
                for channelIndex in 0..<channelCount {
                    let offset = frameIndex * frameStride + channelIndex * MemoryLayout<Float>.size
                    guard offset + MemoryLayout<Float>.size <= Int(buffers[0].mDataByteSize) else { return nil }
                    let sample = source.load(fromByteOffset: offset, as: Float.self)
                    appendClampedInt16(sample, to: &data)
                }
            }
        }

        return data
    }

    private func interleavedInt16Data(
        buffers: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        channelCount: Int,
        audioFormat: AudioStreamBasicDescription,
        isNonInterleaved: Bool,
        isBigEndian: Bool
    ) -> Data? {
        var data = Data()
        data.reserveCapacity(frameCount * channelCount * MemoryLayout<Int16>.size)

        if isNonInterleaved {
            guard buffers.count >= channelCount else { return nil }
            let stride = max(MemoryLayout<Int16>.size, Int(audioFormat.mBytesPerFrame))
            for frameIndex in 0..<frameCount {
                for channelIndex in 0..<channelCount {
                    guard
                        let source = buffers[channelIndex].mData,
                        frameIndex * stride + MemoryLayout<Int16>.size <= Int(buffers[channelIndex].mDataByteSize)
                    else { return nil }
                    let rawSample = source.load(fromByteOffset: frameIndex * stride, as: Int16.self)
                    appendInt16(isBigEndian ? Int16(bigEndian: rawSample) : Int16(littleEndian: rawSample), to: &data)
                }
            }
        } else {
            guard let source = buffers[0].mData else { return nil }
            let frameStride = max(channelCount * MemoryLayout<Int16>.size, Int(audioFormat.mBytesPerFrame))
            for frameIndex in 0..<frameCount {
                for channelIndex in 0..<channelCount {
                    let offset = frameIndex * frameStride + channelIndex * MemoryLayout<Int16>.size
                    guard offset + MemoryLayout<Int16>.size <= Int(buffers[0].mDataByteSize) else { return nil }
                    let rawSample = source.load(fromByteOffset: offset, as: Int16.self)
                    appendInt16(isBigEndian ? Int16(bigEndian: rawSample) : Int16(littleEndian: rawSample), to: &data)
                }
            }
        }

        return data
    }

    private func appendClampedInt16(_ sample: Float, to data: inout Data) {
        let clampedSample = max(-1, min(1, sample))
        let scaledSample = clampedSample == 1 ? Int16.max : Int16(clampedSample * Float(Int16.max))
        appendInt16(scaledSample, to: &data)
    }

    private func appendInt16(_ sample: Int16, to data: inout Data) {
        var littleEndianSample = sample.littleEndian
        withUnsafeBytes(of: &littleEndianSample) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func sendHello() {
        let payload: [String: Any] = [
            "type": "publisher",
            "source": "vibe-check",
            "format": "jpeg",
            "video": [
                "format": "jpeg",
                "transport": "binary",
                "maxDimension": maxDimension,
                "jpegQuality": jpegQuality,
            ],
            "audio": [
                "format": "pcm_s16le",
                "transport": "json-base64",
                "interleaved": true,
            ],
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

    private func send(audio payload: AudioPayload, sequence: Int) {
        var message: [String: Any] = [
            "type": "audio",
            "sequence": sequence,
            "format": "pcm_s16le",
            "sampleRate": payload.sampleRate,
            "channels": payload.channelCount,
            "frames": payload.frameCount,
            "data": payload.data.base64EncodedString(),
        ]
        if let presentationTimeSeconds = payload.presentationTimeSeconds {
            message["pts"] = presentationTimeSeconds
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let string = String(data: data, encoding: .utf8)
        else { return }

        sendQueue.async { [weak self] in
            self?.task?.send(.string(string)) { error in
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

private struct AudioSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

private struct AudioPayload {
    let data: Data
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    let presentationTimeSeconds: Double?
}
