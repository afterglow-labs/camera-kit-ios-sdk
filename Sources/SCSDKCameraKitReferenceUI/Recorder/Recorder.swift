//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import SCSDKCameraKit
import UIKit

/// Records Camera Kit's processed video and audio without silently discarding writer backpressure.
public final class CameraKitRecordingOutput: NSObject, Output, OutputRequiringPixelBuffer {
    private enum State {
        case ready
        case recording
        case finishing
        case finished(URL?, Error?)
    }

    private enum RecordingFailure: LocalizedError {
        case writerDidNotStart(Error?)
        case noVideoAtRequestedResolution(expected: CGSize, observed: CGSize?)
        case videoResolutionChanged(expected: CGSize, observed: CGSize)
        case writerBackpressure(mediaType: String)
        case appendFailed(mediaType: String, underlying: Error?)

        var errorDescription: String? {
            switch self {
            case let .writerDidNotStart(error):
                return "The recording writer could not start: \(error?.localizedDescription ?? "unknown error")"
            case let .noVideoAtRequestedResolution(expected, observed):
                let observedText = observed.map { "\(Int($0.width)) x \(Int($0.height))" } ?? "none"
                return "Camera Kit did not produce the requested \(Int(expected.width)) x \(Int(expected.height)) output; observed \(observedText)."
            case let .videoResolutionChanged(expected, observed):
                return "Camera Kit output changed from \(Int(expected.width)) x \(Int(expected.height)) to \(Int(observed.width)) x \(Int(observed.height)) during recording."
            case let .writerBackpressure(mediaType):
                return "The \(mediaType) encoder did not accept media within five seconds."
            case let .appendFailed(mediaType, underlying):
                return "The \(mediaType) encoder rejected media: \(underlying?.localizedDescription ?? "unknown error")"
            }
        }
    }

    public weak var delegate: SCCameraKitOutputRequiringPixelBufferDelegate?
    public var currentlyRequiresPixelBuffer = false {
        didSet {
            guard oldValue != currentlyRequiresPixelBuffer else { return }
            delegate?.outputChangedRequirements(self)
        }
    }

    private let outputURL: URL
    private let configuration: RecordingConfiguration
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let pixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    private let mediaQueue = DispatchQueue(label: "com.snap.camerakit.reference-ui.recording-media", qos: .userInitiated)
    private let callbackLock = NSLock()
    private let stateLock = NSLock()
    private var acceptingMedia = false
    private var state: State = .ready
    private var finishCompletions: [((URL?, Error?) -> Void)] = []

    private var sessionStartTime: CMTime?
    private var firstVideoPresentationTime: CMTime?
    private var lastVideoEndTime: CMTime?
    private var lastAudioEndTime: CMTime?
    private var pendingAudioBuffers: [CMSampleBuffer] = []
    private var recordingFailure: Error?
    private var lastObservedVideoSize: CGSize?
    private var receivedVideoBuffers = 0
    private var writtenVideoBuffers = 0
    private var receivedAudioBuffers = 0
    private var writtenAudioBuffers = 0
    private var skippedAudioPrerollBuffers = 0
    private var recordingStartUptime: TimeInterval?

    public init(
        url: URL,
        configuration: RecordingConfiguration,
        transform: CGAffineTransform
    ) throws {
        self.outputURL = url
        self.configuration = configuration
        self.writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoOutputSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = transform
        self.videoInput = videoInput

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.audioOutputSettings)
        audioInput.expectsMediaDataInRealTime = true
        self.audioInput = audioInput

        self.pixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: nil
        )

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw RecordingFailure.writerDidNotStart(writer.error)
        }
        writer.add(videoInput)
        writer.add(audioInput)
    }

    public func startRecording() {
        stateLock.lock()
        guard case .ready = state else {
            stateLock.unlock()
            return
        }

        guard writer.startWriting() else {
            let error = RecordingFailure.writerDidNotStart(writer.error)
            state = .finished(nil, error)
            stateLock.unlock()
            return
        }
        state = .recording
        stateLock.unlock()

        callbackLock.lock()
        acceptingMedia = true
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        callbackLock.unlock()
        currentlyRequiresPixelBuffer = true
    }

    public func finishRecording(completion: ((URL?, Error?) -> Void)?) {
        stateLock.lock()
        switch state {
        case .ready:
            let error = RecordingFailure.writerDidNotStart(writer.error)
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

        callbackLock.lock()
        acceptingMedia = false
        callbackLock.unlock()
        currentlyRequiresPixelBuffer = false

        mediaQueue.async { [self] in
            finishWriter()
        }
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputTexture texture: Texture) {}

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        callbackLock.lock()
        guard acceptingMedia else {
            callbackLock.unlock()
            return
        }
        mediaQueue.sync { [self] in
            appendVideo(sampleBuffer)
        }
        callbackLock.unlock()
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        callbackLock.lock()
        guard acceptingMedia else {
            callbackLock.unlock()
            return
        }
        mediaQueue.sync { [self] in
            appendAudio(sampleBuffer)
        }
        callbackLock.unlock()
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard recordingFailure == nil else { return }
        receivedVideoBuffers += 1

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "video", underlying: nil)
            return
        }

        let observedSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        lastObservedVideoSize = observedSize
        guard observedSize == configuration.outputSize else {
            if sessionStartTime == nil {
                if let recordingStartUptime,
                   ProcessInfo.processInfo.systemUptime - recordingStartUptime >= 5 {
                    recordingFailure = RecordingFailure.noVideoAtRequestedResolution(
                        expected: configuration.outputSize,
                        observed: observedSize
                    )
                }
                return
            }
            recordingFailure = RecordingFailure.videoResolutionChanged(
                expected: configuration.outputSize,
                observed: observedSize
            )
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "video", underlying: nil)
            return
        }

        if sessionStartTime == nil {
            writer.startSession(atSourceTime: presentationTime)
            sessionStartTime = presentationTime
            firstVideoPresentationTime = presentationTime
        }

        guard waitUntilReady(videoInput, mediaType: "video") else { return }
        guard pixelBufferInput.append(pixelBuffer, withPresentationTime: presentationTime) else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "video", underlying: writer.error)
            return
        }

        writtenVideoBuffers += 1
        lastVideoEndTime = sampleEndTime(
            sampleBuffer,
            fallbackDuration: CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond))
        )

        if !pendingAudioBuffers.isEmpty {
            let bufferedAudio = pendingAudioBuffers
            pendingAudioBuffers.removeAll(keepingCapacity: false)
            bufferedAudio.forEach(appendAudioAfterSessionStarts)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard recordingFailure == nil else { return }
        receivedAudioBuffers += 1
        guard sessionStartTime != nil else {
            pendingAudioBuffers.append(sampleBuffer)
            return
        }
        appendAudioAfterSessionStarts(sampleBuffer)
    }

    private func appendAudioAfterSessionStarts(_ sampleBuffer: CMSampleBuffer) {
        guard recordingFailure == nil, let sessionStartTime else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "audio", underlying: nil)
            return
        }

        if CMTimeCompare(presentationTime, sessionStartTime) < 0 {
            skippedAudioPrerollBuffers += 1
            return
        }

        guard waitUntilReady(audioInput, mediaType: "audio") else { return }
        guard audioInput.append(sampleBuffer) else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "audio", underlying: writer.error)
            return
        }

        writtenAudioBuffers += 1
        lastAudioEndTime = sampleEndTime(sampleBuffer, fallbackDuration: .zero)
    }

    private func waitUntilReady(_ input: AVAssetWriterInput, mediaType: String) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed || writer.status == .cancelled {
                recordingFailure = RecordingFailure.appendFailed(mediaType: mediaType, underlying: writer.error)
                return false
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                recordingFailure = RecordingFailure.writerBackpressure(mediaType: mediaType)
                return false
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return true
    }

    private func sampleEndTime(_ sampleBuffer: CMSampleBuffer, fallbackDuration: CMTime) -> CMTime {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let resolvedDuration = duration.isValid && duration.isNumeric && duration > .zero
            ? duration
            : fallbackDuration
        return CMTimeAdd(presentationTime, resolvedDuration)
    }

    private func finishWriter() {
        if recordingFailure == nil, sessionStartTime == nil {
            recordingFailure = RecordingFailure.noVideoAtRequestedResolution(
                expected: configuration.outputSize,
                observed: lastObservedVideoSize
            )
        }

        guard recordingFailure == nil else {
            writer.cancelWriting()
            complete(url: nil, error: recordingFailure)
            return
        }

        if let endTime = maximumTime(lastVideoEndTime, lastAudioEndTime) {
            writer.endSession(atSourceTime: endTime)
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        writer.finishWriting { [self] in
            let error = writer.error
            let url = writer.status == .completed ? outputURL : nil
            complete(url: url, error: error)
        }
    }

    private func maximumTime(_ lhs: CMTime?, _ rhs: CMTime?) -> CMTime? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return CMTimeMaximum(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }

    private func complete(url: URL?, error: Error?) {
        let measuredFramesPerSecond: String
        if let firstVideoPresentationTime,
           let lastVideoEndTime {
            let duration = CMTimeGetSeconds(CMTimeSubtract(lastVideoEndTime, firstVideoPresentationTime))
            if duration.isFinite, duration > 0 {
                measuredFramesPerSecond = String(format: "%.2f", Double(writtenVideoBuffers) / duration)
            } else {
                measuredFramesPerSecond = "unavailable"
            }
        } else {
            measuredFramesPerSecond = "unavailable"
        }
        print(
            "[CameraKit Recorder] requested=\(Int(configuration.outputSize.width))x\(Int(configuration.outputSize.height))@\(configuration.framesPerSecond) "
                + "video=\(writtenVideoBuffers)/\(receivedVideoBuffers) audio=\(writtenAudioBuffers)/\(receivedAudioBuffers) "
                + "measuredFPS=\(measuredFramesPerSecond) audioPreroll=\(skippedAudioPrerollBuffers) "
                + "error=\(error?.localizedDescription ?? "none")"
        )

        stateLock.lock()
        state = .finished(url, error)
        let completions = finishCompletions
        finishCompletions.removeAll()
        stateLock.unlock()
        completions.forEach { $0(url, error) }
    }
}

/// Sample video recorder implementation.
public final class Recorder {
    public let output: CameraKitRecordingOutput
    private let orientation: AVCaptureVideoOrientation

    /// Flip captured video horizontally.
    public var horizontallyMirror = false {
        didSet {
            output.setVideoTransform(
                Recorder.affineTransform(orientation: orientation, mirrored: horizontallyMirror)
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
        self.orientation = orientation
        self.output = try CameraKitRecordingOutput(
            url: url,
            configuration: configuration,
            transform: Recorder.affineTransform(orientation: orientation, mirrored: false)
        )
    }

    public func startRecording() {
        output.startRecording()
    }

    public func finishRecording(completion: ((URL?, Error?) -> Void)?) {
        output.finishRecording(completion: completion)
    }

    public static func affineTransform(orientation: AVCaptureVideoOrientation, mirrored: Bool) -> CGAffineTransform {
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

private extension CameraKitRecordingOutput {
    func setVideoTransform(_ transform: CGAffineTransform) {
        mediaQueue.sync {
            videoInput.transform = transform
        }
    }
}
