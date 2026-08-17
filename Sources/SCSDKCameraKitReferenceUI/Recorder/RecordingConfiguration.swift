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

/// Encoder settings for a Camera Kit recording.
public struct RecordingConfiguration {
    public let outputSize: CGSize
    public let framesPerSecond: Int
    public let videoBitRate: Int
    public let videoCodec: AVVideoCodecType
    public let audioSampleRate: Double
    public let audioBitRate: Int
    public let audioChannelCount: Int
    private let requestedVideoBitRate: Int?

    public init(
        outputSize: CGSize,
        framesPerSecond: Int,
        videoBitRate: Int? = nil,
        videoCodec: AVVideoCodecType = .hevc,
        audioSampleRate: Double = 48_000,
        audioBitRate: Int = 192_000,
        audioChannelCount: Int = 1
    ) {
        self.outputSize = OutputSizeHelper.encoderCompatibleSize(outputSize)
        self.framesPerSecond = max(1, framesPerSecond)
        self.requestedVideoBitRate = videoBitRate
        self.videoCodec = videoCodec
        self.videoBitRate = videoBitRate ?? Self.highQualityVideoBitRate(
            outputSize: self.outputSize,
            framesPerSecond: self.framesPerSecond
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
}
