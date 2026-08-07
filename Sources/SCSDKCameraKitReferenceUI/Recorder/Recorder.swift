//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import SCSDKCameraKit
import UIKit

/// Sample video recorder implementation.
public class Recorder {
    private enum State {
        case ready
        case recording
        case finishing
        case finished(URL?, Error?)
    }

    /// The URL to write the video to.
    private let outputURL: URL

    /// The AVWriterOutput for CameraKt.
    public let output: AVWriterOutput
    /// Flip captured video horizontally.
    /// - Attention: If your camera pipeline uses AVFoundation, you do not need to set this property.
    /// - Note: By default this is FALSE. When set to FALSE, the capture will be mirrored on the front and not mirrored on the back camera.
    /// - Note: If set to TRUE, the capture will be mirrored on top of any mirroring done by AVFoundation: Capture is mirrored if either horizontallyMirrored is TRUE or device set to front camera is TRUE. If both are TRUE the two mirroring operations will cancel out.
    public var horizontallyMirror: Bool = false

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    private let stateLock = NSLock()
    private let finalizationQueue = DispatchQueue(label: "com.snap.camerakit.reference-ui.recorder-finalization")
    private var state: State = .ready
    private var finishCompletions: [((URL?, Error?) -> Void)] = []
    private let audioInput: AVAssetWriterInput = {
        let compressionAudioSettings: [String: Any] =
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: 128_000,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: compressionAudioSettings)
        audioInput.expectsMediaDataInRealTime = true
        return audioInput
    }()

    /// Designated init to pass in required deps
    /// - Parameters:
    ///   - url: output URL of video file
    ///   - orientation: current orientation of device
    ///   - size: height of video output
    ///   - mirrored:flip video capture horizontally.  If false, Recorder will automatically mirror capture
    ///   based on AVFoundation camera configuration. If true, Recorder will flip the capture. Set this parameter
    ///   to true when manually mirroring the input with LensProcessor.setInputHorizontallyMirrored.
    /// - Throws: Throws error if cannot create asset writer with output file URL and file type
    public init(url: URL, orientation: AVCaptureVideoOrientation, size: CGSize) throws {
        self.outputURL = url
        self.writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        self.videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoHeightKey: size.height,
                AVVideoWidthKey: size.width,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            ]
        )

        videoInput.transform = Recorder.affineTransform(orientation: orientation, mirrored: self.horizontallyMirror)

        self.pixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
        )

        writer.add(videoInput)
        writer.add(audioInput)

        self.output = AVWriterOutput(avAssetWriter: writer, pixelBufferInput: pixelBufferInput, audioInput: audioInput)
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

        // Stop accepting Camera Kit frames immediately, then let AVAssetWriter flush away from the UI thread.
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

    public static func affineTransform(orientation: AVCaptureVideoOrientation, mirrored: Bool)
        -> CGAffineTransform
    {
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

private extension AVCaptureVideoOrientation {
    var isPortrait: Bool {
        self == .portrait || self == .portraitUpsideDown
    }
}
