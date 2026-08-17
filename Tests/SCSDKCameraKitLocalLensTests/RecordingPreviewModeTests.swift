import XCTest
@testable import SCSDKCameraKitReferenceUI

final class RecordingPreviewModeTests: XCTestCase {
    func testAllModesShowLensPreviewBeforeRecording() {
        for mode in RecordingPreviewMode.allCases {
            XCTAssertEqual(
                RecordingPreviewPresentation.resolve(mode: mode, isRecording: false),
                RecordingPreviewPresentation(attachesLensOutput: true, showsRawCamera: false)
            )
        }
    }

    func testLensModeKeepsProcessedPreviewAttachedWhileRecording() {
        XCTAssertEqual(
            RecordingPreviewPresentation.resolve(mode: .lens, isRecording: true),
            RecordingPreviewPresentation(attachesLensOutput: true, showsRawCamera: false)
        )
    }

    func testRawCameraModeDetachesProcessedPreviewWhileRecording() {
        XCTAssertEqual(
            RecordingPreviewPresentation.resolve(mode: .rawCamera, isRecording: true),
            RecordingPreviewPresentation(attachesLensOutput: false, showsRawCamera: true)
        )
    }

    func testHiddenModeDetachesAllOnScreenVideoWhileRecording() {
        XCTAssertEqual(
            RecordingPreviewPresentation.resolve(mode: .hidden, isRecording: true),
            RecordingPreviewPresentation(attachesLensOutput: false, showsRawCamera: false)
        )
    }
}
