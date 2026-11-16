import AVFoundation
import CoreMedia
import SCSDKCameraKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

/// Records synthetic capture media through the real writer and inspects the file it produces.
///
/// The microphone tone identifies when each buffer was captured: audio captured during second `k` is a
/// `500 + 250k` Hz sine. Hearing the wrong tone at a given time means the audio has shifted.
final class RecordingOutputAudioTests: XCTestCase {
    func testUninterruptedAudioIsRecordedWhereItWasCaptured() async throws {
        let recording = try await record(seconds: 3) { _ in true }

        XCTAssertEqual(recording.audioEndSeconds, 3.0, accuracy: 0.1)
        for second in 0 ..< 3 {
            XCTAssertEqual(
                recording.toneFrequency(at: Double(second) + 0.5),
                Self.tone(forCaptureSecond: second),
                accuracy: 30
            )
        }
    }

    func testAudioLostInCaptureBecomesSilenceInsteadOfShiftingLaterAudio() async throws {
        // Four seconds of picture; the microphone loses everything captured during the second second.
        let recording = try await record(seconds: 4) { captureSecond in !(1.0 ..< 2.0).contains(captureSecond) }

        XCTAssertEqual(recording.audioEndSeconds, 4.0, accuracy: 0.1, "Lost audio must not shorten the track")
        XCTAssertEqual(recording.toneFrequency(at: 0.5), Self.tone(forCaptureSecond: 0), accuracy: 30)
        XCTAssertLessThan(recording.loudness(at: 1.5), 0.01, "The hole must be silent")
        XCTAssertEqual(recording.toneFrequency(at: 2.5), Self.tone(forCaptureSecond: 2), accuracy: 30)
        XCTAssertEqual(recording.toneFrequency(at: 3.5), Self.tone(forCaptureSecond: 3), accuracy: 30)
    }

    func testManySmallHolesDoNotAddUpToAShift() async throws {
        // Every eighth microphone buffer is lost, as happens when the capture callback keeps running late.
        var bufferIndex = 0
        let recording = try await record(seconds: 4) { _ in
            defer { bufferIndex += 1 }
            return bufferIndex % 8 != 7
        }

        XCTAssertEqual(recording.audioEndSeconds, 4.0, accuracy: 0.1, "Lost audio must not shorten the track")
        XCTAssertEqual(recording.toneFrequency(at: 3.5), Self.tone(forCaptureSecond: 3), accuracy: 40)
    }

    func testAudioStampedWithoutDurationsIsNotPaddedWithSilence() async throws {
        let recording = try await record(seconds: 3, statesAudioDurations: false) { _ in true }

        XCTAssertEqual(recording.audioEndSeconds, 3.0, accuracy: 0.1)
        XCTAssertEqual(recording.toneFrequency(at: 1.5), Self.tone(forCaptureSecond: 1), accuracy: 30)
        XCTAssertEqual(recording.toneFrequency(at: 2.5), Self.tone(forCaptureSecond: 2), accuracy: 30)
    }

    func testAudioThatStartsLateStaysLate() async throws {
        let recording = try await record(seconds: 3) { captureSecond in captureSecond >= 1.0 }

        XCTAssertLessThan(recording.loudness(at: 0.5), 0.01, "Nothing was captured in the first second")
        XCTAssertEqual(recording.toneFrequency(at: 1.5), Self.tone(forCaptureSecond: 1), accuracy: 30)
        XCTAssertEqual(recording.toneFrequency(at: 2.5), Self.tone(forCaptureSecond: 2), accuracy: 30)
    }

    // MARK: Recording

    private static let framesPerSecond = 30
    private static let audioFramesPerBuffer = 1_024

    private static func tone(forCaptureSecond second: Int) -> Double {
        500 + 250 * Double(second)
    }

    /// Records `seconds` of picture at 30 fps with microphone buffers arriving in capture order.
    /// `keepsAudio` is asked once per microphone buffer, with its capture time in seconds, whether the
    /// buffer reaches the recorder.
    private func record(
        seconds: Int,
        statesAudioDurations: Bool = true,
        keepsAudio: (Double) -> Bool
    ) async throws -> RecordedAudio {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let recorder = try Recorder(
            url: url,
            orientation: .portrait,
            configuration: RecordingConfiguration(
                outputSize: CGSize(width: 320, height: 240),
                framesPerSecond: Self.framesPerSecond,
                videoCodec: .h264
            )
        )
        let cameraKit = SharedControllers.withBuiltInCamera.cameraKit
        // Capture clocks do not start at zero.
        let start = CMTime(value: 1_000, timescale: 1)
        let totalAudioFrames = seconds * Int(MediaSamples.audioSampleRate)
        var nextAudioFrame = 0

        func deliverAudio(capturedBefore captureSecond: Double) throws {
            while nextAudioFrame < totalAudioFrames,
                  Double(nextAudioFrame) / MediaSamples.audioSampleRate <= captureSecond {
                let bufferSecond = Double(nextAudioFrame) / MediaSamples.audioSampleRate
                if keepsAudio(bufferSecond) {
                    let time = CMTimeAdd(
                        start,
                        CMTime(value: CMTimeValue(nextAudioFrame), timescale: CMTimeScale(MediaSamples.audioSampleRate))
                    )
                    recorder.output.cameraKit(
                        cameraKit,
                        didOutputAudioSampleBuffer: try MediaSamples.audio(
                            frames: Self.audioFramesPerBuffer,
                            presentationTime: time,
                            firstFrameIndex: nextAudioFrame,
                            tone: Self.tone(forCaptureSecond: Int(bufferSecond)),
                            statesDuration: statesAudioDurations
                        )
                    )
                }
                nextAudioFrame += Self.audioFramesPerBuffer
            }
        }

        recorder.startRecording()
        for frame in 0 ..< seconds * Self.framesPerSecond {
            let time = CMTimeAdd(start, CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Self.framesPerSecond)))
            recorder.output.cameraKit(
                cameraKit,
                didOutputVideoSampleBuffer: try MediaSamples.video(width: 320, height: 240, presentationTime: time)
            )
            try deliverAudio(capturedBefore: Double(frame) / Double(Self.framesPerSecond))
        }
        try deliverAudio(capturedBefore: Double(seconds))

        let recordedURL: URL? = await withCheckedContinuation { continuation in
            recorder.finishRecording { url, _ in continuation.resume(returning: url) }
        }
        return try await RecordedAudio(url: try XCTUnwrap(recordedURL, "The recording did not finish"))
    }
}

/// The decoded audio track of a recording, addressed in movie time.
private struct RecordedAudio {
    let audioEndSeconds: Double
    private let samples: [Float]
    private let firstSampleSeconds: Double
    private static let sampleRate = 48_000.0

    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first, "The recording has no audio track")
        let timeRange = try await track.load(.timeRange)
        audioEndSeconds = timeRange.end.seconds

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var decoded: [Float] = []
        var firstTime: Double?
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if firstTime == nil {
                firstTime = sampleBuffer.presentationTimeStamp.seconds
            }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var bytes = [Int16](repeating: 0, count: byteCount / MemoryLayout<Int16>.size)
            XCTAssertEqual(
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: &bytes),
                kCMBlockBufferNoErr
            )
            decoded.append(contentsOf: bytes.map { Float($0) / Float(Int16.max) })
        }
        samples = decoded
        firstSampleSeconds = firstTime ?? timeRange.start.seconds
    }

    /// Frequency of the tone playing at `seconds` of movie time, from the spacing of zero crossings over
    /// 100 ms. Using the typical spacing rather than a count keeps short silent stretches from lowering it.
    func toneFrequency(at seconds: Double) -> Double {
        let window = self.window(at: seconds)
        var crossings: [Int] = []
        for index in window.indices.dropFirst() where (window[index - 1] < 0) != (window[index] < 0) {
            crossings.append(index)
        }
        let spacings = zip(crossings, crossings.dropFirst()).map { $1 - $0 }.sorted()
        guard spacings.count >= 4 else { return 0 }
        let typical = spacings[spacings.count / 4 ..< spacings.count * 3 / 4]
        let halfPeriod = Double(typical.reduce(0, +)) / Double(typical.count)
        return Self.sampleRate / (2 * halfPeriod)
    }

    /// Root-mean-square level over 100 ms at `seconds` of movie time; full scale is 1.
    func loudness(at seconds: Double) -> Double {
        let window = self.window(at: seconds)
        guard !window.isEmpty else { return 0 }
        let meanSquare = window.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(window.count)
        return meanSquare.squareRoot()
    }

    private func window(at seconds: Double) -> [Float] {
        let first = Int((seconds - firstSampleSeconds) * Self.sampleRate)
        let last = first + Int(0.1 * Self.sampleRate)
        guard first >= 0, last <= samples.count else { return [] }
        return Array(samples[first ..< last])
    }
}
