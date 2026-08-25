import AVFoundation
import CoreMedia
import CoreVideo
import SCSDKCameraKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class ExternalInputCompatibilityAdapterTests: XCTestCase {
    func testVideoRangeNV12IsConvertedToFullRangeNV12() throws {
        let sourceBuffer = try makePixelBuffer(
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            width: 16,
            height: 16
        )
        try fillVideoRangeBlack(sourceBuffer)
        let sourceSample = try makeSampleBuffer(
            imageBuffer: sourceBuffer,
            presentationTimeStamp: CMTime(value: 7, timescale: 30)
        )

        let converter = ExternalInputVideoFrameConverter()
        let convertedSample = try XCTUnwrap(converter.cameraKitCompatibleSampleBuffer(sourceSample))
        let convertedBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(convertedSample))

        XCTAssertEqual(
            CVPixelBufferGetPixelFormatType(convertedBuffer),
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )
        XCTAssertEqual(CVPixelBufferGetWidth(convertedBuffer), 16)
        XCTAssertEqual(CVPixelBufferGetHeight(convertedBuffer), 16)
        XCTAssertEqual(convertedSample.presentationTimeStamp, sourceSample.presentationTimeStamp)

        CVPixelBufferLockBaseAddress(convertedBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(convertedBuffer, .readOnly) }
        let convertedLuma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(convertedBuffer, 0))
            .assumingMemoryBound(to: UInt8.self)
        XCTAssertLessThanOrEqual(convertedLuma[0], 2, "video-range black must map to full-range black")
    }

    func testAlreadySupportedFullRangeNV12PassesThrough() throws {
        let sourceBuffer = try makePixelBuffer(
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            width: 16,
            height: 16
        )
        let sourceSample = try makeSampleBuffer(imageBuffer: sourceBuffer)

        let converter = ExternalInputVideoFrameConverter()
        let outputSample = try XCTUnwrap(converter.cameraKitCompatibleSampleBuffer(sourceSample))
        let outputBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(outputSample))

        XCTAssertTrue(outputBuffer === sourceBuffer)
    }

    private func makePixelBuffer(
        pixelFormat: OSType,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    private func fillVideoRangeBlack(_ pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0))
        memset(luma, 16, CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

        let chroma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1))
        memset(
            chroma,
            128,
            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        )
    }

    private func makeSampleBuffer(
        imageBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime = .zero
    ) throws -> CMSampleBuffer {
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
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTimeStamp,
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
}
