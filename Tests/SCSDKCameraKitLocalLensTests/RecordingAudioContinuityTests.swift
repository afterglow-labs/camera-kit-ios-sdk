import CoreMedia
import XCTest
@testable import SCSDKCameraKitReferenceUI

/// The audio writer packs buffers back to back and ignores their timestamps after the first one, so a
/// hole left by lost audio would make everything after it play early. The recorder writes silence for
/// the hole instead; this works out how much.
final class RecordingAudioContinuityTests: XCTestCase {
    private let bufferDuration = CMTime(value: 1_024, timescale: 48_000)

    func testTheFirstBufferNeedsNoSilence() {
        let continuity = RecordingAudioContinuity()

        let silence = continuity.silenceNeeded(before: seconds(100), newestVideoTime: seconds(100))

        XCTAssertEqual(silence, .zero)
    }

    func testABufferThatFollowsOnNeedsNoSilence() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        let next = CMTimeAdd(seconds(100), bufferDuration)

        let silence = continuity.silenceNeeded(before: next, newestVideoTime: next)

        XCTAssertEqual(silence, .zero)
    }

    func testAHoleLeftByLostAudioNeedsSilenceOfTheSameLength() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        // The three buffers after the first one never arrived.
        let next = CMTimeAdd(seconds(100), CMTimeMultiply(bufferDuration, multiplier: 4))

        let silence = continuity.silenceNeeded(before: next, newestVideoTime: next)

        XCTAssertEqual(silence.seconds, 3 * bufferDuration.seconds, accuracy: 0.000_1)
    }

    func testAHoleTooShortToNoticeIsLeftAlone() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        // One lost buffer is 21 ms: far too little to see as a sync error, and no more than the wobble
        // some sources have in their timestamps.
        let next = CMTimeAdd(seconds(100), CMTimeMultiply(bufferDuration, multiplier: 2))

        let silence = continuity.silenceNeeded(before: next, newestVideoTime: next)

        XCTAssertEqual(silence, .zero)
    }

    func testNoMoreSilenceIsNeededOnceTheHoleHasBeenFilled() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        let next = CMTimeAdd(seconds(100), CMTimeMultiply(bufferDuration, multiplier: 4))
        let silence = continuity.silenceNeeded(before: next, newestVideoTime: next)

        continuity.didWrite(duration: silence, at: CMTimeAdd(seconds(100), bufferDuration))

        XCTAssertEqual(continuity.silenceNeeded(before: next, newestVideoTime: next), .zero)
    }

    func testTimestampJitterIsNotTreatedAsLostAudio() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        let fiveMillisecondsLate = CMTimeAdd(CMTimeAdd(seconds(100), bufferDuration), seconds(0.005))

        let silence = continuity.silenceNeeded(before: fiveMillisecondsLate, newestVideoTime: fiveMillisecondsLate)

        XCTAssertEqual(silence, .zero)
    }

    func testSmallGapsAreFilledOnceTheyAddUpToMoreThanJitter() {
        var continuity = RecordingAudioContinuity()
        var captureTime = seconds(100)
        var silence = CMTime.zero
        // One buffer in every two is lost, so each one that arrives is a further 21 ms behind.
        var silences: [Double] = []
        for _ in 0 ..< 3 {
            silence = continuity.silenceNeeded(before: captureTime, newestVideoTime: captureTime)
            silences.append(silence.seconds)
            continuity.didWrite(duration: bufferDuration, at: captureTime)
            captureTime = CMTimeAdd(captureTime, CMTimeMultiply(bufferDuration, multiplier: 2))
        }

        XCTAssertEqual(silences[0], 0)
        XCTAssertEqual(silences[1], 0, "One lost buffer alone is too short to fill")
        XCTAssertEqual(silences[2], 2 * bufferDuration.seconds, accuracy: 0.000_1)
    }

    func testAudioWhoseTimestampsOverlapIsLeftAlone() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))

        let silence = continuity.silenceNeeded(before: seconds(100.01), newestVideoTime: seconds(101))

        XCTAssertEqual(silence, .zero)
    }

    func testAudioStampedFarAheadOfThePictureIsNotPadded() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))

        // An hour ahead of the newest frame means a different clock, not an hour of lost audio.
        let silence = continuity.silenceNeeded(before: seconds(3_700), newestVideoTime: seconds(100.5))

        XCTAssertEqual(silence, .zero)
    }

    func testAHoleIsFilledOnceThePictureCatchesUpWithIt() {
        var continuity = RecordingAudioContinuity()
        continuity.didWrite(duration: bufferDuration, at: seconds(100))
        let afterTheHole = seconds(105)
        XCTAssertEqual(continuity.silenceNeeded(before: afterTheHole, newestVideoTime: seconds(101)), .zero)

        let silence = continuity.silenceNeeded(before: afterTheHole, newestVideoTime: seconds(104.5))

        XCTAssertEqual(silence.seconds, 5 - bufferDuration.seconds, accuracy: 0.000_1)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 1_000_000)
    }
}

final class RecordingSilenceTests: XCTestCase {
    func testSilenceHasTheFormatAndTimingOfTheAudioItStandsInFor() throws {
        let audio = try MediaSamples.audio(frames: 1_024, presentationTime: CMTime(value: 9, timescale: 1), tone: 440)
        let duration = CMTime(value: 2_048, timescale: 48_000)
        let presentationTime = CMTime(value: 7, timescale: 1)

        let silence = try XCTUnwrap(
            RecordingSilence.makeSampleBuffer(matching: audio, duration: duration, presentationTime: presentationTime)
        )

        XCTAssertEqual(CMSampleBufferGetNumSamples(silence), 2_048)
        XCTAssertEqual(silence.presentationTimeStamp, presentationTime)
        XCTAssertTrue(
            CMFormatDescriptionEqual(silence.formatDescription, otherFormatDescription: audio.formatDescription)
        )
        let data = try XCTUnwrap(CMSampleBufferGetDataBuffer(silence))
        var bytes = [UInt8](repeating: 1, count: CMBlockBufferGetDataLength(data))
        XCTAssertEqual(bytes.count, 2_048 * 2)
        XCTAssertEqual(
            CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes.count, destination: &bytes),
            kCMBlockBufferNoErr
        )
        XCTAssertTrue(bytes.allSatisfy { $0 == 0 })
    }

    func testSilenceShorterThanOneAudioFrameIsNotMade() throws {
        let audio = try MediaSamples.audio()

        let silence = RecordingSilence.makeSampleBuffer(
            matching: audio,
            duration: CMTime(value: 1, timescale: 1_000_000),
            presentationTime: .zero
        )

        XCTAssertNil(silence)
    }
}
