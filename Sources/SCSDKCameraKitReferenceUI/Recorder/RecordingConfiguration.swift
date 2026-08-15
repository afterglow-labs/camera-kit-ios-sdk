//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import CoreGraphics

/// Encoder settings for a Camera Kit recording.
public struct RecordingConfiguration {
    public let outputSize: CGSize
    public let framesPerSecond: Int
    public let videoBitRate: Int
    public let audioSampleRate: Double
    public let audioBitRate: Int
    public let audioChannelCount: Int

    public init(
        outputSize: CGSize,
        framesPerSecond: Int,
        videoBitRate: Int? = nil,
        audioSampleRate: Double = 48_000,
        audioBitRate: Int = 192_000,
        audioChannelCount: Int = 1
    ) {
        self.outputSize = OutputSizeHelper.encoderCompatibleSize(outputSize)
        self.framesPerSecond = max(1, framesPerSecond)
        self.videoBitRate = videoBitRate ?? Self.highQualityVideoBitRate(
            outputSize: self.outputSize,
            framesPerSecond: self.framesPerSecond
        )
        self.audioSampleRate = audioSampleRate
        self.audioBitRate = audioBitRate
        self.audioChannelCount = audioChannelCount
    }

    var videoOutputSettings: [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
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
