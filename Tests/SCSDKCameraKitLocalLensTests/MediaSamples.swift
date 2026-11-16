import AVFoundation
import CoreMedia
import CoreVideo
import XCTest

/// Synthetic capture samples for recording and routing tests.
enum MediaSamples {
    static let audioSampleRate = 48_000.0

    /// 16-bit mono PCM stamped with `presentationTime`. A `tone` in hertz fills the buffer with a sine
    /// whose phase continues from `firstFrameIndex`; without one the buffer is silent. Some sources stamp
    /// audio without a duration; `statesDuration: false` makes such a buffer.
    static func audio(
        frames: Int = 1_024,
        presentationTime: CMTime = .zero,
        firstFrameIndex: Int = 0,
        tone: Double? = nil,
        statesDuration: Bool = true
    ) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: audioSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )

        var samples = [Int16](repeating: 0, count: frames)
        if let tone {
            for index in 0 ..< frames {
                let frame = Double(firstFrameIndex + index)
                samples[index] = Int16(12_000.0 * sin(2.0 * Double.pi * tone * frame / audioSampleRate))
            }
        }

        let byteCount = frames * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        XCTAssertEqual(
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            ),
            kCMBlockBufferNoErr
        )
        let dataBuffer = try XCTUnwrap(blockBuffer)
        try samples.withUnsafeBytes { bytes in
            XCTAssertEqual(
                CMBlockBufferReplaceDataBytes(
                    with: try XCTUnwrap(bytes.baseAddress),
                    blockBuffer: dataBuffer,
                    offsetIntoDestination: 0,
                    dataLength: byteCount
                ),
                kCMBlockBufferNoErr
            )
        }

        var sampleBuffer: CMSampleBuffer?
        if statesDuration {
            XCTAssertEqual(
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: dataBuffer,
                    formatDescription: try XCTUnwrap(formatDescription),
                    sampleCount: frames,
                    presentationTimeStamp: presentationTime,
                    packetDescriptions: nil,
                    sampleBufferOut: &sampleBuffer
                ),
                noErr
            )
        } else {
            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: .invalid
            )
            var sampleSize = MemoryLayout<Int16>.size
            XCTAssertEqual(
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: dataBuffer,
                    formatDescription: try XCTUnwrap(formatDescription),
                    sampleCount: frames,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleSizeEntryCount: 1,
                    sampleSizeArray: &sampleSize,
                    sampleBufferOut: &sampleBuffer
                ),
                noErr
            )
        }
        return try XCTUnwrap(sampleBuffer)
    }

    /// A full-range NV12 frame, the format Camera Kit hands to recording outputs.
    static func video(
        width: Int = 64,
        height: Int = 64,
        presentationTime: CMTime = .zero
    ) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                attributes as CFDictionary,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        let imageBuffer = try XCTUnwrap(pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        XCTAssertEqual(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescription: try XCTUnwrap(formatDescription),
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return try XCTUnwrap(sampleBuffer)
    }

    /// Duration in seconds of the first track of `mediaType`, or nil when the file has no such track.
    static func trackSeconds(_ mediaType: AVMediaType, in url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: mediaType).first else { return nil }
        return try await track.load(.timeRange).duration.seconds
    }
}
