import AVFoundation
import CoreGraphics
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class RecordingConfigurationTests: XCTestCase {
    func testFullScreenFourKOutputKeepsTheSelectedLongEdgeAndEvenDimensions() {
        let outputSize = OutputSizeHelper.normalizedSize(
            for: CGSize(width: 2_160, height: 3_840),
            aspectRatio: 402.0 / 874.0
        )

        XCTAssertEqual(outputSize, CGSize(width: 1_766, height: 3_840))
    }

    func testFourKSixtyConfigurationReachesTheVideoEncoder() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 2_160, height: 3_840),
            framesPerSecond: 60
        )

        XCTAssertEqual(configuration.videoOutputSettings[AVVideoWidthKey] as? Int, 2_160)
        XCTAssertEqual(configuration.videoOutputSettings[AVVideoHeightKey] as? Int, 3_840)

        let compression = configuration.videoOutputSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
        XCTAssertEqual(compression?[AVVideoAverageBitRateKey] as? Int, 99_532_800)
    }

    func testRecordingAudioUsesHighQualityAACSettings() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30
        )

        XCTAssertEqual(configuration.audioOutputSettings[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(configuration.audioOutputSettings[AVEncoderBitRateKey] as? Int, 192_000)
        XCTAssertEqual(configuration.audioOutputSettings[AVNumberOfChannelsKey] as? Int, 1)
    }

    func testRecordingResolutionOutputDoesNotChangeLensViewportCoordinates() {
        let output = RecordingResolutionOutput()
        output.setOutputResolution(CGSize(width: 1_766, height: 3_840))

        XCTAssertEqual(output.outputResolution, CGSize(width: 1_766, height: 3_840))
        XCTAssertEqual(output.viewportSize, .zero)
        XCTAssertTrue(output.safeArea.isNull)
    }
}
