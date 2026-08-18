import AVFoundation
import CoreGraphics
import VideoToolbox
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class RecordingConfigurationTests: XCTestCase {
    func testCameraRecordingUsesNativeVideoRecordingAudioProfile() {
        XCTAssertEqual(CameraKitAudioSession.category, .playAndRecord)
        XCTAssertEqual(CameraKitAudioSession.mode, .videoRecording)
        XCTAssertEqual(CameraKitAudioSession.preferredSampleRate, 48_000)
        XCTAssertTrue(CameraKitAudioSession.options.contains(.defaultToSpeaker))
        XCTAssertFalse(CameraKitAudioSession.options.contains(.allowBluetoothHFP))
    }

    func testRecorderUsesCameraKitNativeWriterOutput() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try Recorder(
            url: url,
            orientation: .portrait,
            configuration: RecordingConfiguration(
                outputSize: CGSize(width: 1_080, height: 1_920),
                framesPerSecond: 30
            )
        )

        XCTAssertEqual(String(describing: type(of: recorder.output)), "SCCameraKitAVWriterOutput")
    }

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

    func testHighDefinitionModeRaisesAutomatic1080pThirtyBitRate() {
        let standard = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30
        )
        let highDefinition = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30,
            highDefinitionModeEnabled: true
        )

        XCTAssertEqual(standard.videoBitRate, 12_441_600)
        XCTAssertEqual(highDefinition.videoBitRate, 16_000_000)
    }

    func testManualBitRateRemainsAuthoritativeInHighDefinitionMode() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30,
            videoBitRate: 30_000_000,
            highDefinitionModeEnabled: true
        )

        XCTAssertEqual(configuration.videoBitRate, 30_000_000)
    }

    func testReplacingOutputSizePreservesHighDefinitionBitRatePolicy() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 720, height: 1_280),
            framesPerSecond: 30,
            highDefinitionModeEnabled: true
        )

        let promoted = configuration.replacingOutputSize(CGSize(width: 1_080, height: 1_920))

        XCTAssertEqual(promoted.videoBitRate, 16_000_000)
    }

    func testCameraRecordingUsesTheSelectedHEVCCodec() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30,
            videoCodec: .hevc
        )

        XCTAssertEqual(configuration.videoOutputSettings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)

        let compression = configuration.videoOutputSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoProfileLevelKey] as? String, kVTProfileLevel_HEVC_Main_AutoLevel as String)
    }

    func testCameraRecordingUsesTheSelectedH264Codec() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30,
            videoCodec: .h264
        )

        XCTAssertEqual(configuration.videoOutputSettings[AVVideoCodecKey] as? AVVideoCodecType, .h264)

        let compression = configuration.videoOutputSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoProfileLevelKey] as? String, AVVideoProfileLevelH264HighAutoLevel)
    }

    func testReplacingOutputSizePreservesTheSelectedCodec() {
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_080, height: 1_920),
            framesPerSecond: 30,
            videoCodec: .hevc
        )

        let resized = configuration.replacingOutputSize(CGSize(width: 1_440, height: 1_920))

        XCTAssertEqual(resized.videoOutputSettings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
    }

    func testRecordingCodecResolverUsesTheCameraRecommendedCodec() {
        let codec = RecordingVideoCodecResolver.resolve(
            recommendedSettings: [AVVideoCodecKey: AVVideoCodecType.h264],
            availableCodecs: [.hevc, .h264]
        )

        XCTAssertEqual(codec, .h264)
    }

    func testRecordingCodecResolverFallsBackToTheMostEfficientAvailableCodec() {
        let codec = RecordingVideoCodecResolver.resolve(
            recommendedSettings: nil,
            availableCodecs: [.hevc, .h264]
        )

        XCTAssertEqual(codec, .hevc)
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
        let configuration = RecordingConfiguration(
            outputSize: CGSize(width: 1_766, height: 3_840),
            framesPerSecond: 30
        )
        let output = RecordingResolutionOutput()
        output.setOutputResolution(configuration.outputSize)

        XCTAssertEqual(output.outputResolution, configuration.outputSize)
        XCTAssertEqual(output.viewportSize, .zero)
        XCTAssertTrue(output.safeArea.isNull)
    }

    func testLensRenderingKeepsLandscapeFourK() {
        XCTAssertEqual(
            LensRenderingResolution.fullResolution(for: CGSize(width: 3_840, height: 2_160)),
            CGSize(width: 3_840, height: 2_160)
        )
    }

    func testLensRenderingKeepsPortraitFourK() {
        XCTAssertEqual(
            LensRenderingResolution.fullResolution(for: CGSize(width: 2_160, height: 3_840)),
            CGSize(width: 2_160, height: 3_840)
        )
    }

    func testLensRenderingKeepsNative1440pAspectRatio() {
        XCTAssertEqual(
            LensRenderingResolution.fullResolution(for: CGSize(width: 1_440, height: 1_920)),
            CGSize(width: 1_440, height: 1_920)
        )
    }

    func testLensRenderingDoesNotUpscaleSmallerOutput() {
        XCTAssertEqual(
            LensRenderingResolution.fullResolution(for: CGSize(width: 1_280, height: 720)),
            CGSize(width: 1_280, height: 720)
        )
    }

    func testLensRenderingRejectsInvalidCameraDimensions() {
        XCTAssertEqual(
            LensRenderingResolution.fullResolution(for: CGSize(width: CGFloat.infinity, height: 1_080)),
            .zero
        )
        XCTAssertEqual(LensRenderingResolution.fullResolution(for: .zero), .zero)
    }

    func testHighDefinitionLensRenderingRequiresExplicitOptInAndAnActiveLens() {
        let sourceSize = CGSize(width: 1_080, height: 1_920)

        XCTAssertNil(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: false,
                lensActive: true,
                sourceSize: sourceSize
            )
        )
        XCTAssertNil(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: true,
                lensActive: false,
                sourceSize: sourceSize
            )
        )
        XCTAssertEqual(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: true,
                lensActive: true,
                sourceSize: sourceSize
            ),
            sourceSize
        )
    }

    func testHighDefinitionLensRenderingDoesNotReadSourceUntilItCanApply() {
        var sourceReadCount = 0
        func sourceSize() -> CGSize {
            sourceReadCount += 1
            return CGSize(width: 1_080, height: 1_920)
        }

        XCTAssertNil(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: false,
                lensActive: true,
                sourceSize: sourceSize()
            )
        )
        XCTAssertEqual(sourceReadCount, 0)

        XCTAssertNil(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: true,
                lensActive: false,
                sourceSize: sourceSize()
            )
        )
        XCTAssertEqual(sourceReadCount, 0)

        XCTAssertEqual(
            HighDefinitionLensRenderingPolicy.overrideSize(
                enabled: true,
                lensActive: true,
                sourceSize: sourceSize()
            ),
            CGSize(width: 1_080, height: 1_920)
        )
        XCTAssertEqual(sourceReadCount, 1)
    }

    func testHighDefinitionCameraFormatPromotesNative720pTo1080p() {
        let preferred = HighDefinitionCameraFormatPolicy.preferredDimensions(
            requested: CGSize(width: 1_280, height: 720),
            available: [
                CGSize(width: 1_280, height: 720),
                CGSize(width: 1_920, height: 1_080),
                CGSize(width: 3_840, height: 2_160),
            ]
        )

        XCTAssertEqual(preferred, CGSize(width: 1_920, height: 1_080))
    }

    func testHighDefinitionCameraFormatPromotesFourByThreeToNative1440p() {
        let preferred = HighDefinitionCameraFormatPolicy.preferredDimensions(
            requested: CGSize(width: 1_280, height: 960),
            available: [
                CGSize(width: 1_280, height: 960),
                CGSize(width: 1_920, height: 1_080),
                CGSize(width: 1_920, height: 1_440),
            ]
        )

        XCTAssertEqual(preferred, CGSize(width: 1_920, height: 1_440))
    }

    func testHighDefinitionCameraFormatDoesNotFakeAnUnsupportedAspectRatio() {
        let preferred = HighDefinitionCameraFormatPolicy.preferredDimensions(
            requested: CGSize(width: 1_280, height: 960),
            available: [
                CGSize(width: 1_280, height: 960),
                CGSize(width: 1_920, height: 1_080),
            ]
        )

        XCTAssertNil(preferred)
    }

    func testHighDefinitionCameraFormatKeepsAnAlreadyHighDefinitionNativeFormat() {
        let preferred = HighDefinitionCameraFormatPolicy.preferredDimensions(
            requested: CGSize(width: 1_920, height: 1_080),
            available: [
                CGSize(width: 1_280, height: 720),
                CGSize(width: 1_920, height: 1_080),
                CGSize(width: 3_840, height: 2_160),
            ]
        )

        XCTAssertEqual(preferred, CGSize(width: 1_920, height: 1_080))
    }
}
