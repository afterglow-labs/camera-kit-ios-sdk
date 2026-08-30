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

    func testUIKitLensCarouselUsesAdaptiveSafeAreaClearance() {
        for width in [320.0, 375.0, 393.0, 600.0] {
            let cameraView = laidOutCameraView(width: width)
            let safeFrame = cameraView.safeAreaLayoutGuide.layoutFrame
            let expectedInset = CameraCaptureChromeLayout.trailingClearance(
                for: safeFrame.width
            )

            XCTAssertEqual(
                safeFrame.maxX - cameraView.carouselView.frame.maxX,
                expectedInset,
                accuracy: 0.5,
                "Unexpected UIKit Lens carousel inset at width \(width)"
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
            cameraView.cameraActionsView.noseAdjustmentsActionView.toggleButton.accessibilityLabel,
            "Nose Adjustments"
        )
        XCTAssertTrue(cameraView.cameraActionsView.noseAdjustmentsActionView.configurable)
        XCTAssertEqual(
            cameraView.cameraActionsView.noseAdjustmentsActionView.configurationButton.accessibilityLabel,
            "Nose Adjustment Settings"
        )
    }

    func testNoseAdjustmentPresetsMatchTheAuthoredLensValues() {
        XCTAssertEqual(
            NoseAdjustmentPreset.petite.values,
            NoseAdjustmentValues(width: -0.45, height: -0.25, gap: -0.15)
        )
        XCTAssertEqual(
            NoseAdjustmentPreset.refined.values,
            NoseAdjustmentValues(width: -0.28, height: 0.18, gap: -0.20)
        )
        XCTAssertEqual(
            NoseAdjustmentPreset.lifted.values,
            NoseAdjustmentValues(width: -0.18, height: 0.34, gap: 0.18)
        )
        XCTAssertEqual(
            NoseAdjustmentPreset.sculpted.values,
            NoseAdjustmentValues(width: -0.38, height: 0.42, gap: 0.05)
        )
        XCTAssertEqual(
            NoseAdjustmentPreset.soft.values,
            NoseAdjustmentValues(width: 0.18, height: -0.16, gap: -0.12)
        )
        XCTAssertEqual(
            NoseAdjustmentPreset.bold.values,
            NoseAdjustmentValues(width: 0.35, height: 0.20, gap: 0.16)
        )
    }

    func testNoseAdjustmentValuesClampToLensRange() {
        XCTAssertEqual(
            NoseAdjustmentValues(width: -2, height: 2, gap: 0.25),
            NoseAdjustmentValues(width: -1, height: 1, gap: 0.25)
        )
    }

    func testNoseAdjustmentPanelFitsCompactCameraWidth() {
        let cameraView = laidOutCameraView(width: 320)
        let panel = cameraView.noseAdjustmentsControlView
        let safeFrame = cameraView.safeAreaLayoutGuide.layoutFrame
        let action = cameraView.cameraActionsView.noseAdjustmentsActionView
        let actionFrame = action.convert(action.bounds, to: cameraView)

        XCTAssertGreaterThanOrEqual(panel.frame.minX, safeFrame.minX + 8 - 0.5)
        XCTAssertLessThan(panel.frame.maxX, actionFrame.minX)
        XCTAssertEqual(panel.frame.width, 220, accuracy: 0.5)
    }

    func testNoseStyleSliderUpdatesAllFineControls() {
        let control = NoseAdjustmentsControlView()

        control.controlSlider(
            control.styleSlider,
            updatedValue: Float(NoseAdjustmentPreset.sculpted.rawValue),
            done: true
        )

        XCTAssertEqual(control.selectedPreset, .sculpted)
        XCTAssertEqual(control.values.width, NoseAdjustmentPreset.sculpted.values.width, accuracy: 0.0001)
        XCTAssertEqual(control.values.height, NoseAdjustmentPreset.sculpted.values.height, accuracy: 0.0001)
        XCTAssertEqual(control.values.gap, NoseAdjustmentPreset.sculpted.values.gap, accuracy: 0.0001)
        XCTAssertEqual(control.styleValueLabel.text, "Sculpted")
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
