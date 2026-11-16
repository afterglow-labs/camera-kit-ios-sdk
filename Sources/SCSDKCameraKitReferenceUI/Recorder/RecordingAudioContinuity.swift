//  Copyright Snap Inc. All rights reserved.

import CoreMedia

/// Works out how much silence the recorder must write so that audio stays at its capture time.
///
/// The audio writer places the first buffer at its timestamp and then packs everything after it back to
/// back, ignoring later timestamps. If capture loses audio, everything after the hole would therefore play
/// early. Writing silence for the hole keeps the rest where it was captured.
struct RecordingAudioContinuity {
    /// Gaps up to this long are left alone. A shift this small cannot be seen as a sync error, and leaving
    /// it keeps wobble in a source's timestamps from being mistaken for lost audio. Gaps add up, so
    /// repeated small losses are still filled once together they pass this.
    static let tolerance = CMTime(value: 3, timescale: 100)

    /// Audio stamped further than this beyond the newest video frame is not padded. A timestamp that far
    /// ahead of the picture comes from a different clock, and padding it would push all later audio late.
    /// A real hole is filled once the picture catches up with it.
    static let videoLead = CMTime(value: 1, timescale: 1)

    /// Where the writer will place the next audio it is given.
    private var writePosition: CMTime?

    /// How much silence to write before a buffer captured at `presentationTime`. Zero when the buffer
    /// follows on from the audio written so far.
    func silenceNeeded(before presentationTime: CMTime, newestVideoTime: CMTime) -> CMTime {
        guard let writePosition,
              presentationTime <= CMTimeAdd(newestVideoTime, Self.videoLead) else {
            return .zero
        }
        let gap = CMTimeSubtract(presentationTime, writePosition)
        return gap > Self.tolerance ? gap : .zero
    }

    /// Records audio or silence handed to the writer. Only the first timestamp matters to the writer.
    mutating func didWrite(duration: CMTime, at presentationTime: CMTime) {
        if let writePosition {
            self.writePosition = CMTimeAdd(writePosition, duration)
        } else {
            writePosition = CMTimeAdd(presentationTime, duration)
        }
    }
}

enum RecordingSilence {
    /// The longest stretch of silence made as one buffer; a longer hole is filled in several steps.
    static let maximumDuration = CMTime(value: 1, timescale: 1)

    /// Silent PCM in the format of `sampleBuffer`, or nil when that audio is not PCM or `duration` is
    /// shorter than one audio frame.
    static func makeSampleBuffer(
        matching sampleBuffer: CMSampleBuffer,
        duration: CMTime,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        guard duration.isValid, duration.isNumeric, duration > .zero,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mSampleRate > 0,
              streamDescription.mBytesPerFrame > 0 else {
            return nil
        }

        let frameCount = Int((duration.seconds * streamDescription.mSampleRate).rounded())
        guard frameCount > 0 else { return nil }

        // Non-interleaved PCM stores one plane per channel, each `mBytesPerFrame` wide.
        let isNonInterleaved = streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let planeCount = isNonInterleaved ? Int(max(streamDescription.mChannelsPerFrame, 1)) : 1
        let byteCount = frameCount * Int(streamDescription.mBytesPerFrame) * planeCount

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr,
            let blockBuffer,
            CMBlockBufferFillDataBytes(
                with: 0,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            ) == kCMBlockBufferNoErr else {
            return nil
        }

        var silence: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &silence
        ) == noErr else {
            return nil
        }
        return silence
    }
}
