//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import SCSDKCameraKit
import UIKit

/// Records Camera Kit's processed audio and video through Camera Kit's native writer output.
public final class Recorder {
    private enum State {
        case ready
        case recording
        case finishing
        case finished(URL?, Error?)
    }

    private enum RecorderError: LocalizedError {
        case cannotAddMediaInputs(Error?)

        var errorDescription: String? {
            switch self {
            case let .cannotAddMediaInputs(error):
                return "The recording writer rejected its media inputs: \(error?.localizedDescription ?? "unknown error")"
            }
        }
    }

    private let outputURL: URL
    private let orientation: AVCaptureVideoOrientation
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let pixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    private let stateLock = NSLock()
    private let finalizationQueue = DispatchQueue(label: "com.snap.camerakit.reference-ui.recorder-finalization")
    private var state: State = .ready
    private var finishCompletions: [((URL?, Error?) -> Void)] = []

    /// Camera Kit's synchronized audio/video writer output.
    public let output: AVWriterOutput

    /// Flip captured video horizontally.
    public var horizontallyMirror = false {
        didSet {
            stateLock.lock()
            let canUpdateTransform: Bool
            if case .ready = state {
                canUpdateTransform = true
            } else {
                canUpdateTransform = false
            }
            stateLock.unlock()

            guard canUpdateTransform else { return }
            videoInput.transform = Recorder.affineTransform(
                orientation: orientation,
                mirrored: horizontallyMirror
            )
        }
    }

    public convenience init(url: URL, orientation: AVCaptureVideoOrientation, size: CGSize) throws {
        try self.init(
            url: url,
            orientation: orientation,
            configuration: RecordingConfiguration(outputSize: size, framesPerSecond: 30)
        )
    }

    public init(
        url: URL,
        orientation: AVCaptureVideoOrientation,
        configuration: RecordingConfiguration
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: configuration.videoOutputSettings
        )
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = Recorder.affineTransform(orientation: orientation, mirrored: false)

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: configuration.audioOutputSettings
        )
        audioInput.expectsMediaDataInRealTime = true

        let pixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
        )

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw RecorderError.cannotAddMediaInputs(writer.error)
        }
        writer.add(videoInput)
        writer.add(audioInput)

        self.outputURL = url
        self.orientation = orientation
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferInput = pixelBufferInput
        self.output = AVWriterOutput(
            avAssetWriter: writer,
            pixelBufferInput: pixelBufferInput,
            audioInput: audioInput
        )
    }

    public func startRecording() {
        stateLock.lock()
        guard case .ready = state else {
            stateLock.unlock()
            return
        }

        guard writer.startWriting() else {
            let error = writer.error
            state = .finished(nil, error)
            stateLock.unlock()
            return
        }
        state = .recording
        stateLock.unlock()

        output.startRecording()
    }

    public func finishRecording(completion: ((URL?, Error?) -> Void)?) {
        stateLock.lock()
        switch state {
        case .ready:
            let error = writer.error
            state = .finished(nil, error)
            stateLock.unlock()
            completion?(nil, error)
            return
        case .recording:
            if let completion {
                finishCompletions.append(completion)
            }
            state = .finishing
            stateLock.unlock()
        case .finishing:
            if let completion {
                finishCompletions.append(completion)
            }
            stateLock.unlock()
            return
        case let .finished(url, error):
            stateLock.unlock()
            completion?(url, error)
            return
        }

        output.stopRecording()
        finalizationQueue.async { [self] in
            videoInput.markAsFinished()
            audioInput.markAsFinished()
            writer.finishWriting { [self] in
                let error = writer.error
                let url = writer.status == .completed ? outputURL : nil

                stateLock.lock()
                state = .finished(url, error)
                let completions = finishCompletions
                finishCompletions.removeAll()
                stateLock.unlock()

                completions.forEach { $0(url, error) }
            }
        }
    }

    public static func affineTransform(
        orientation: AVCaptureVideoOrientation,
        mirrored: Bool
    ) -> CGAffineTransform {
        var transform: CGAffineTransform = .identity
        switch orientation {
        case .portraitUpsideDown:
            transform = transform.rotated(by: .pi)
        case .landscapeRight:
            transform = transform.rotated(by: .pi / 2)
        case .landscapeLeft:
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }

        if mirrored {
            transform = transform.scaledBy(x: -1, y: 1)
        }
        return transform
    }
}
