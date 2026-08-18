//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import CoreGraphics
import VideoToolbox

enum RecordingVideoCodecResolver {
    static func resolve(
        recommendedSettings: [String: Any]?,
        availableCodecs: [AVVideoCodecType]
    ) -> AVVideoCodecType {
        if let recommendedCodec = codec(in: recommendedSettings),
           availableCodecs.isEmpty || availableCodecs.contains(recommendedCodec) {
            return recommendedCodec
        }

        return availableCodecs.first ?? .hevc
    }

    private static func codec(in settings: [String: Any]?) -> AVVideoCodecType? {
        guard let value = settings?[AVVideoCodecKey] else { return nil }
        if let codec = value as? AVVideoCodecType {
            return codec
        }
        if let rawValue = value as? String {
            return AVVideoCodecType(rawValue: rawValue)
        }
        return nil
    }
}

enum LensRenderingResolution {
    static func fullResolution(for inputSize: CGSize) -> CGSize {
        guard inputSize.width.isFinite,
              inputSize.height.isFinite,
              inputSize.width > 0,
              inputSize.height > 0 else {
            return .zero
        }

        return OutputSizeHelper.encoderCompatibleSize(inputSize)
    }
}

enum HighDefinitionLensRenderingPolicy {
    static func overrideSize(enabled: Bool, lensActive: Bool, sourceSize: CGSize) -> CGSize? {
        guard enabled, lensActive else { return nil }
        let resolvedSize = LensRenderingResolution.fullResolution(for: sourceSize)
        return resolvedSize == .zero ? nil : resolvedSize
    }
}

/// Resolves the smallest native capture size that satisfies Camera Kit's HD floor without changing aspect ratio.
public enum HighDefinitionCameraFormatPolicy {
    public static let minimumShortEdge: CGFloat = 1_080

    public static func preferredDimensions(requested: CGSize, available: [CGSize]) -> CGSize? {
        guard let requestedGeometry = geometry(for: requested) else { return nil }
        let requiredShortEdge = max(requestedGeometry.shortEdge, minimumShortEdge)

        return available
            .compactMap { size -> (size: CGSize, geometry: Geometry)? in
                guard let geometry = geometry(for: size) else { return nil }
                guard abs(geometry.aspectRatio - requestedGeometry.aspectRatio) < 0.01 else { return nil }
                guard geometry.shortEdge >= requiredShortEdge else { return nil }
                return (size, geometry)
            }
            .min { left, right in
                if left.geometry.shortEdge != right.geometry.shortEdge {
                    return left.geometry.shortEdge < right.geometry.shortEdge
                }
                return left.geometry.pixelCount < right.geometry.pixelCount
            }?
            .size
    }

    private struct Geometry {
        let shortEdge: CGFloat
        let aspectRatio: CGFloat
        let pixelCount: CGFloat
    }

    private static func geometry(for size: CGSize) -> Geometry? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let shortEdge = min(size.width, size.height)
        let longEdge = max(size.width, size.height)
        return Geometry(
            shortEdge: shortEdge,
            aspectRatio: longEdge / shortEdge,
            pixelCount: shortEdge * longEdge
        )
    }
}

/// Encoder settings for a Camera Kit recording.
public struct RecordingConfiguration {
    public let outputSize: CGSize
    public let framesPerSecond: Int
    public let videoBitRate: Int
    public let highDefinitionModeEnabled: Bool
    public let videoCodec: AVVideoCodecType
    public let audioSampleRate: Double
    public let audioBitRate: Int
    public let audioChannelCount: Int
    private let requestedVideoBitRate: Int?

    public init(
        outputSize: CGSize,
        framesPerSecond: Int,
        videoBitRate: Int? = nil,
        highDefinitionModeEnabled: Bool = false,
        videoCodec: AVVideoCodecType = .hevc,
        audioSampleRate: Double = 48_000,
        audioBitRate: Int = 192_000,
        audioChannelCount: Int = 1
    ) {
        self.outputSize = OutputSizeHelper.encoderCompatibleSize(outputSize)
        self.framesPerSecond = max(1, framesPerSecond)
        self.requestedVideoBitRate = videoBitRate
        self.highDefinitionModeEnabled = highDefinitionModeEnabled
        self.videoCodec = videoCodec
        self.videoBitRate = videoBitRate ?? Self.automaticVideoBitRate(
            outputSize: self.outputSize,
            framesPerSecond: self.framesPerSecond,
            highDefinitionModeEnabled: highDefinitionModeEnabled
        )
        self.audioSampleRate = audioSampleRate
        self.audioBitRate = audioBitRate
        self.audioChannelCount = audioChannelCount
    }

    func replacingOutputSize(_ outputSize: CGSize) -> RecordingConfiguration {
        RecordingConfiguration(
            outputSize: outputSize,
            framesPerSecond: framesPerSecond,
            videoBitRate: requestedVideoBitRate,
            highDefinitionModeEnabled: highDefinitionModeEnabled,
            videoCodec: videoCodec,
            audioSampleRate: audioSampleRate,
            audioBitRate: audioBitRate,
            audioChannelCount: audioChannelCount
        )
    }

    func replacingVideoCodec(_ videoCodec: AVVideoCodecType) -> RecordingConfiguration {
        RecordingConfiguration(
            outputSize: outputSize,
            framesPerSecond: framesPerSecond,
            videoBitRate: requestedVideoBitRate,
            highDefinitionModeEnabled: highDefinitionModeEnabled,
            videoCodec: videoCodec,
            audioSampleRate: audioSampleRate,
            audioBitRate: audioBitRate,
            audioChannelCount: audioChannelCount
        )
    }

    func replacingHighDefinitionModeEnabled(_ enabled: Bool) -> RecordingConfiguration {
        RecordingConfiguration(
            outputSize: outputSize,
            framesPerSecond: framesPerSecond,
            videoBitRate: requestedVideoBitRate,
            highDefinitionModeEnabled: enabled,
            videoCodec: videoCodec,
            audioSampleRate: audioSampleRate,
            audioBitRate: audioBitRate,
            audioChannelCount: audioChannelCount
        )
    }

    var videoOutputSettings: [String: Any] {
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitRate,
            AVVideoExpectedSourceFrameRateKey: framesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
        ]
        switch videoCodec {
        case .h264:
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            compressionProperties[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        default:
            break
        }

        return [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compressionProperties,
        ]
    }

    var audioOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: audioBitRate,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: audioChannelCount,
        ]
    }

    private static func highQualityVideoBitRate(outputSize: CGSize, framesPerSecond: Int) -> Int {
        let pixelsPerSecond = outputSize.width * outputSize.height * CGFloat(framesPerSecond)
        return Int((pixelsPerSecond * 0.2).rounded())
    }

    private static func automaticVideoBitRate(
        outputSize: CGSize,
        framesPerSecond: Int,
        highDefinitionModeEnabled: Bool
    ) -> Int {
        let baseline = highQualityVideoBitRate(
            outputSize: outputSize,
            framesPerSecond: framesPerSecond
        )
        guard highDefinitionModeEnabled else { return baseline }

        let pixelsPerSecond = outputSize.width * outputSize.height * CGFloat(framesPerSecond)
        let referencePixelsPerSecond = CGFloat(1_920 * 1_080 * 30)
        let scaledHighDefinitionBitRate = Int(
            (CGFloat(16_000_000) * pixelsPerSecond / referencePixelsPerSecond).rounded()
        )
        return max(baseline, scaledHighDefinitionBitRate)
    }
}
