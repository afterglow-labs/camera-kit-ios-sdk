//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import SCSDKCameraKit
import UIKit

/// Records Camera Kit's processed video and audio without dropping media during writer backpressure.
public final class CameraKitRecordingOutput: NSObject, Output, OutputRequiringPixelBuffer {
    private enum State {
        case ready
        case recording
        case finishing
        case finished(URL?, Error?)
    }

    private enum RecordingFailure: LocalizedError {
        case writerDidNotStart(Error?)
        case noVideoSamples
        case invalidSample(mediaType: String)
        case appendFailed(mediaType: String, underlying: Error?)

        var errorDescription: String? {
            switch self {
            case let .writerDidNotStart(error):
                return "The recording writer could not start: \(error?.localizedDescription ?? "unknown error")"
            case .noVideoSamples:
                return "Camera Kit did not produce a video sample for this recording."
            case let .invalidSample(mediaType):
                return "Camera Kit produced an invalid \(mediaType) sample."
            case let .appendFailed(mediaType, underlying):
                return "The \(mediaType) encoder rejected media: \(underlying?.localizedDescription ?? "unknown error")"
            }
        }
    }

    private struct SampleBufferQueue {
        private var storage: [CMSampleBuffer] = []
        private var head = 0

        var isEmpty: Bool { head == storage.count }
        var count: Int { storage.count - head }
        var first: CMSampleBuffer? { isEmpty ? nil : storage[head] }

        mutating func append(_ sampleBuffer: CMSampleBuffer) {
            storage.append(sampleBuffer)
        }

        @discardableResult
        mutating func popFirst() -> CMSampleBuffer? {
            guard !isEmpty else { return nil }
            let sampleBuffer = storage[head]
            head += 1
            compactIfNeeded()
            return sampleBuffer
        }

        mutating func removeAll() {
            storage.removeAll(keepingCapacity: false)
            head = 0
        }

        private mutating func compactIfNeeded() {
            guard head >= 64, head * 2 >= storage.count else { return }
            storage.removeFirst(head)
            head = 0
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
    private let mediaQueue = DispatchQueue(
        label: "com.snap.camerakit.reference-ui.recording-media",
        qos: .userInitiated
    )
    private let callbackLock = NSLock()
    private let stateLock = NSLock()

    private var acceptingMedia = false
    private var state: State = .ready
    private var finishCompletions: [((URL?, Error?) -> Void)] = []

    private var sessionStartTime: CMTime?
    private var firstVideoPresentationTime: CMTime?
    private var lastVideoEndTime: CMTime?
    private var lastAudioEndTime: CMTime?
    private var pendingVideoBuffers = SampleBufferQueue()
    private var pendingAudioBuffers = SampleBufferQueue()
    private var recordingFailure: Error?
    private var videoInputFinished = false
    private var audioInputFinished = false
    private var writerFinishStarted = false

    private var receivedVideoBuffers = 0
    private var writtenVideoBuffers = 0
    private var receivedAudioBuffers = 0
    private var writtenAudioBuffers = 0
    private var skippedAudioPrerollBuffers = 0

    public init(
        url: URL,
        configuration: RecordingConfiguration,
        transform: CGAffineTransform
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: configuration.videoOutputSettings
        )
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = transform

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
            throw RecordingFailure.writerDidNotStart(writer.error)
        }
        writer.add(videoInput)
        writer.add(audioInput)

        self.outputURL = url
        self.configuration = configuration
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferInput = pixelBufferInput
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
            beginFinishing()
        }
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputTexture texture: Texture) {}

    public func cameraKit(
        _ cameraKit: CameraKitProtocol,
        didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer
    ) {
        callbackLock.lock()
        guard acceptingMedia else {
            callbackLock.unlock()
            return
        }
        mediaQueue.async { [self, sampleBuffer] in
            enqueueVideo(sampleBuffer)
        }
        callbackLock.unlock()
    }

    public func cameraKit(
        _ cameraKit: CameraKitProtocol,
        didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer
    ) {
        callbackLock.lock()
        guard acceptingMedia else {
            callbackLock.unlock()
            return
        }
        mediaQueue.async { [self, sampleBuffer] in
            enqueueAudio(sampleBuffer)
        }
        callbackLock.unlock()
    }

    func setVideoTransform(_ transform: CGAffineTransform) {
        mediaQueue.sync {
            videoInput.transform = transform
        }
    }

    private func enqueueVideo(_ sampleBuffer: CMSampleBuffer) {
        guard recordingFailure == nil else { return }
        receivedVideoBuffers += 1

        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            recordingFailure = RecordingFailure.invalidSample(mediaType: "video")
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric else {
            recordingFailure = RecordingFailure.invalidSample(mediaType: "video")
            return
        }

        if sessionStartTime == nil {
            writer.startSession(atSourceTime: presentationTime)
            sessionStartTime = presentationTime
            firstVideoPresentationTime = presentationTime
        }

        pendingVideoBuffers.append(sampleBuffer)
        drainVideoBuffers()
        drainAudioBuffers()
    }

    private func enqueueAudio(_ sampleBuffer: CMSampleBuffer) {
        guard recordingFailure == nil else { return }
        receivedAudioBuffers += 1
        pendingAudioBuffers.append(sampleBuffer)
        drainAudioBuffers()
    }

    private func drainVideoBuffers() {
        while recordingFailure == nil,
              videoInput.isReadyForMoreMediaData,
              let sampleBuffer = pendingVideoBuffers.first {
            _ = pendingVideoBuffers.popFirst()
            appendVideoToWriter(sampleBuffer)
        }
    }

    private func appendVideoToWriter(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            recordingFailure = RecordingFailure.invalidSample(mediaType: "video")
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pixelBufferInput.append(pixelBuffer, withPresentationTime: presentationTime) else {
            recordingFailure = RecordingFailure.appendFailed(mediaType: "video", underlying: writer.error)
            return
        }

        writtenVideoBuffers += 1
        lastVideoEndTime = sampleEndTime(
            sampleBuffer,
            fallbackDuration: CMTime(
                value: 1,
                timescale: CMTimeScale(max(configuration.framesPerSecond, 1))
            )
        )
    }

    private func drainAudioBuffers() {
        guard let sessionStartTime else { return }

        while recordingFailure == nil, let sampleBuffer = pendingAudioBuffers.first {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isValid, presentationTime.isNumeric else {
                _ = pendingAudioBuffers.popFirst()
                recordingFailure = RecordingFailure.invalidSample(mediaType: "audio")
                return
            }

            if CMTimeCompare(presentationTime, sessionStartTime) < 0 {
                _ = pendingAudioBuffers.popFirst()
                skippedAudioPrerollBuffers += 1
                continue
            }

            guard audioInput.isReadyForMoreMediaData else { return }
            _ = pendingAudioBuffers.popFirst()
            guard audioInput.append(sampleBuffer) else {
                recordingFailure = RecordingFailure.appendFailed(mediaType: "audio", underlying: writer.error)
                return
            }

            writtenAudioBuffers += 1
            lastAudioEndTime = sampleEndTime(sampleBuffer, fallbackDuration: .zero)
        }
    }

    private func beginFinishing() {
        guard recordingFailure == nil else {
            cancelAndComplete(error: recordingFailure)
            return
        }
        guard sessionStartTime != nil else {
            cancelAndComplete(error: RecordingFailure.noVideoSamples)
            return
        }

        drainVideoBuffers()
        drainAudioBuffers()
        guard recordingFailure == nil else {
            cancelAndComplete(error: recordingFailure)
            return
        }

        if pendingVideoBuffers.isEmpty {
            markVideoInputFinished()
        } else {
            videoInput.requestMediaDataWhenReady(on: mediaQueue) { [weak self] in
                self?.drainVideoBuffersForFinish()
            }
        }

        if pendingAudioBuffers.isEmpty {
            markAudioInputFinished()
        } else {
            audioInput.requestMediaDataWhenReady(on: mediaQueue) { [weak self] in
                self?.drainAudioBuffersForFinish()
            }
        }

        finishWriterIfReady()
    }

    private func drainVideoBuffersForFinish() {
        guard !writerFinishStarted else { return }
        drainVideoBuffers()
        guard recordingFailure == nil else {
            cancelAndComplete(error: recordingFailure)
            return
        }
        guard pendingVideoBuffers.isEmpty else { return }
        markVideoInputFinished()
        finishWriterIfReady()
    }

    private func drainAudioBuffersForFinish() {
        guard !writerFinishStarted else { return }
        drainAudioBuffers()
        guard recordingFailure == nil else {
            cancelAndComplete(error: recordingFailure)
            return
        }
        guard pendingAudioBuffers.isEmpty else { return }
        markAudioInputFinished()
        finishWriterIfReady()
    }

    private func markVideoInputFinished() {
        guard !videoInputFinished else { return }
        videoInputFinished = true
        videoInput.markAsFinished()
    }

    private func markAudioInputFinished() {
        guard !audioInputFinished else { return }
        audioInputFinished = true
        audioInput.markAsFinished()
    }

    private func finishWriterIfReady() {
        guard videoInputFinished, audioInputFinished, !writerFinishStarted else { return }
        writerFinishStarted = true

        if let endTime = maximumTime(lastVideoEndTime, lastAudioEndTime) {
            writer.endSession(atSourceTime: endTime)
        }

        writer.finishWriting { [self] in
            let error = writer.error
            let url = writer.status == .completed ? outputURL : nil
            complete(url: url, error: error)
        }
    }

    private func cancelAndComplete(error: Error?) {
        guard !writerFinishStarted else { return }
        writerFinishStarted = true
        pendingVideoBuffers.removeAll()
        pendingAudioBuffers.removeAll()
        writer.cancelWriting()
        complete(url: nil, error: error ?? writer.error)
    }

    private func sampleEndTime(_ sampleBuffer: CMSampleBuffer, fallbackDuration: CMTime) -> CMTime {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let resolvedDuration = duration.isValid && duration.isNumeric && duration > .zero
            ? duration
            : fallbackDuration
        return CMTimeAdd(presentationTime, resolvedDuration)
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
        if let firstVideoPresentationTime, let lastVideoEndTime {
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
