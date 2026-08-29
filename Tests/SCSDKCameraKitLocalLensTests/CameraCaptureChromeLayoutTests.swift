import UIKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class CameraCaptureChromeLayoutTests: XCTestCase {
    func testLensControlsUseAdaptiveSafeAreaClearance() {
        for width in [320.0, 393.0, 600.0] {
            let cameraView = laidOutCameraView(width: width)
            let safeFrame = cameraView.safeAreaLayoutGuide.layoutFrame
            let expectedInset = CameraActionsView.adaptiveTrailingInset(
                forAvailableWidth: safeFrame.width
            )

            XCTAssertEqual(
                safeFrame.maxX - cameraView.cameraActionsView.frame.maxX,
                expectedInset,
                accuracy: 0.5,
                "Unexpected Lens Controls inset at width \(width)"
            )
        }
    }

    func testCompactCameraChromeMovesFurtherInsideTheViewport() {
        XCTAssertEqual(CameraCaptureChromeLayout.trailingClearance(for: 320), 28)
        XCTAssertEqual(CameraCaptureChromeLayout.trailingClearance(for: 375), 28)
        XCTAssertEqual(CameraCaptureChromeLayout.trailingClearance(for: 393), 24)
        XCTAssertEqual(CameraCaptureChromeLayout.trailingClearance(for: 430), 20)
    }

    func testNoseAdjustmentsControlUsesTheLensName() {
        let cameraView = laidOutCameraView()

        XCTAssertEqual(
            cameraView.cameraActionsView.rhinoplastyActionView.toggleButton.accessibilityLabel,
            "Nose Adjustments"
        )
    }

    func testPhotoAndRecordButtonsAreAtLeastFiftyPercentLarger() {
        let cameraView = laidOutCameraView()

        XCTAssertGreaterThanOrEqual(cameraView.photoCaptureButton.bounds.width, 51)
        XCTAssertGreaterThanOrEqual(cameraView.photoCaptureButton.bounds.height, 51)
        XCTAssertGreaterThanOrEqual(cameraView.videoCaptureButton.bounds.width, 57)
        XCTAssertGreaterThanOrEqual(cameraView.videoCaptureButton.bounds.height, 57)
    }

    func testRecordButtonIsCenteredWithPhotoButtonToItsLeft() {
        let cameraView = laidOutCameraView()
        let photoFrame = cameraView.photoCaptureButton.convert(cameraView.photoCaptureButton.bounds, to: cameraView)
        let recordFrame = cameraView.videoCaptureButton.convert(cameraView.videoCaptureButton.bounds, to: cameraView)

        XCTAssertEqual(recordFrame.midX, cameraView.bounds.midX, accuracy: 0.5)
        XCTAssertLessThan(photoFrame.maxX, recordFrame.minX)
    }

    func testCaptureButtonsClearTheRaisedBottomChrome() {
        let cameraView = laidOutCameraView()
        let bottomClearance = cameraView.bounds.maxY - cameraView.captureControlsView.frame.maxY

        XCTAssertGreaterThanOrEqual(bottomClearance, 116)
    }

    func testAttributionUsesElevenPointTextAndSitsAboveTheRaisedChrome() {
        let cameraView = laidOutCameraView()
        let bottomClearance = cameraView.bounds.maxY - cameraView.snapAttributionView.frame.maxY

        XCTAssertEqual(cameraView.snapAttributionView.poweredByLabel.font.pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(bottomClearance, 108, accuracy: 1)
    }

    func testTemporaryLensStatusIsCenteredBelowTheUnsafeTopRegion() {
        let cameraView = laidOutCameraView()
        cameraView.messageView.label.text = "Lens name\nLens ID"
        cameraView.messageView.label.numberOfLines = 2
        cameraView.setNeedsLayout()
        cameraView.layoutIfNeeded()

        XCTAssertEqual(cameraView.messageView.frame.midX, cameraView.bounds.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            cameraView.messageView.frame.minY,
            cameraView.safeAreaInsets.top + 72
        )
    }

    private func laidOutCameraView(
        width: CGFloat = 393
    ) -> SCSDKCameraKitReferenceUI.CameraView {
        let cameraView = SCSDKCameraKitReferenceUI.CameraView(
            frame: CGRect(x: 0, y: 0, width: width, height: 852)
        )
        cameraView.setNeedsLayout()
        cameraView.layoutIfNeeded()
        return cameraView
    }
}
