import UIKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class CameraCaptureChromeLayoutTests: XCTestCase {
    func testIPhone16ProUsesTheUnmodifiedBaselineGeometry() {
        let metrics = CameraCaptureChromeLayout.metrics(
            for: CameraCaptureChromeLayout.iPhone16ProViewport
        )

        XCTAssertEqual(metrics.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(metrics.photoButtonDiameter, 52, accuracy: 0.01)
        XCTAssertEqual(metrics.videoButtonDiameter, 58, accuracy: 0.01)
        XCTAssertEqual(metrics.captureControlSpacing, 18, accuracy: 0.01)
        XCTAssertEqual(metrics.captureControlsHeight, 64, accuracy: 0.01)
        XCTAssertEqual(metrics.swiftUIFooterBottomPadding, 76, accuracy: 0.01)
        XCTAssertEqual(metrics.attributionFontSize, 11, accuracy: 0.01)
    }

    func testOtherDevicesUseOneUniformScaleFromTheIPhone16Pro() {
        let compactViewport = CGSize(width: 375, height: 812)
        let expectedScale = min(375.0 / 402.0, 812.0 / 874.0)
        let metrics = CameraCaptureChromeLayout.metrics(for: compactViewport)

        XCTAssertEqual(metrics.scale, expectedScale, accuracy: 0.0001)
        XCTAssertEqual(metrics.photoButtonDiameter, 52 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(metrics.videoButtonDiameter, 58 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(metrics.captureControlSpacing, 18 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(metrics.captureControlsHeight, 64 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(metrics.swiftUIFooterBottomPadding, 76 * expectedScale, accuracy: 0.01)
        XCTAssertEqual(metrics.attributionFontSize, 11 * expectedScale, accuracy: 0.01)
    }

    func testInvalidViewportFallsBackToBaselineScale() {
        XCTAssertEqual(
            CameraCaptureChromeLayout.metrics(for: .zero).scale,
            1,
            accuracy: 0.0001
        )
    }

    func testNoseAdjustmentsControlUsesTheLensName() {
        let cameraView = laidOutCameraView()

        XCTAssertEqual(
            cameraView.cameraActionsView.rhinoplastyActionView.toggleButton.accessibilityLabel,
            "Nose Adjustments"
        )
    }

    func testUIKitRestoresTheBaselineCaptureGroup() {
        let cameraView = laidOutCameraView()
        let photoFrame = cameraView.photoCaptureButton.convert(
            cameraView.photoCaptureButton.bounds,
            to: cameraView
        )
        let videoFrame = cameraView.videoCaptureButton.convert(
            cameraView.videoCaptureButton.bounds,
            to: cameraView
        )
        let groupFrame = cameraView.captureControlsView.convert(
            cameraView.captureControlsView.bounds,
            to: cameraView
        )

        XCTAssertEqual(photoFrame.width, 52, accuracy: 0.5)
        XCTAssertEqual(videoFrame.width, 58, accuracy: 0.5)
        XCTAssertEqual(groupFrame.midX, cameraView.bounds.midX, accuracy: 0.5)
        XCTAssertLessThan(photoFrame.maxX, videoFrame.minX)
        XCTAssertEqual(cameraView.bounds.maxY - groupFrame.maxY, 116, accuracy: 0.5)
    }

    func testUIKitScalesTheSameBaselineOnACompactViewport() {
        let viewport = CGSize(width: 375, height: 812)
        let cameraView = laidOutCameraView(width: viewport.width, height: viewport.height)
        let metrics = CameraCaptureChromeLayout.metrics(for: viewport)
        let photoFrame = cameraView.photoCaptureButton.convert(
            cameraView.photoCaptureButton.bounds,
            to: cameraView
        )
        let videoFrame = cameraView.videoCaptureButton.convert(
            cameraView.videoCaptureButton.bounds,
            to: cameraView
        )

        XCTAssertEqual(photoFrame.width, metrics.photoButtonDiameter, accuracy: 0.5)
        XCTAssertEqual(videoFrame.width, metrics.videoButtonDiameter, accuracy: 0.5)
        XCTAssertEqual(
            cameraView.bounds.maxY - cameraView.captureControlsView.frame.maxY,
            116 * metrics.scale,
            accuracy: 0.5
        )
    }

    func testUIKitScalesButtonsInsideTheCameraActionsStrip() {
        let viewport = CGSize(width: 375, height: 812)
        let cameraView = laidOutCameraView(width: viewport.width, height: viewport.height)
        let metrics = CameraCaptureChromeLayout.metrics(for: viewport)
        let flipFrame = cameraView.cameraActionsView.flipCameraButton.convert(
            cameraView.cameraActionsView.flipCameraButton.bounds,
            to: cameraView
        )
        let flashFrame = cameraView.cameraActionsView.flashActionView.toggleButton.convert(
            cameraView.cameraActionsView.flashActionView.toggleButton.bounds,
            to: cameraView
        )

        XCTAssertEqual(flipFrame.width, 40 * metrics.scale, accuracy: 0.5)
        XCTAssertEqual(flipFrame.height, 40 * metrics.scale, accuracy: 0.5)
        XCTAssertEqual(flashFrame.width, 40 * metrics.scale, accuracy: 0.5)
        XCTAssertEqual(flashFrame.height, 40 * metrics.scale, accuracy: 0.5)
    }

    func testAttributionContentRemainsInsideItsBounds() {
        for viewport in [CGSize(width: 375, height: 812), CameraCaptureChromeLayout.iPhone16ProViewport] {
            let cameraView = laidOutCameraView(width: viewport.width, height: viewport.height)
            let attribution = cameraView.snapAttributionView
            let iconFrame = attribution.snapIconImage.convert(
                attribution.snapIconImage.bounds,
                to: attribution
            )
            let labelFrame = attribution.poweredByLabel.convert(
                attribution.poweredByLabel.bounds,
                to: attribution
            )
            let attributionFrame = attribution.convert(attribution.bounds, to: cameraView)

            XCTAssertGreaterThan(attribution.bounds.width, 0)
            XCTAssertGreaterThanOrEqual(labelFrame.minX, attribution.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(labelFrame.maxX, attribution.bounds.maxX + 0.5)
            XCTAssertLessThanOrEqual(iconFrame.maxX, attribution.bounds.maxX + 0.5)
            XCTAssertLessThanOrEqual(attributionFrame.maxX, cameraView.safeAreaLayoutGuide.layoutFrame.maxX)
        }
    }

    private func laidOutCameraView(
        width: CGFloat = CameraCaptureChromeLayout.iPhone16ProViewport.width,
        height: CGFloat = CameraCaptureChromeLayout.iPhone16ProViewport.height
    ) -> SCSDKCameraKitReferenceUI.CameraView {
        let cameraView = SCSDKCameraKitReferenceUI.CameraView(
            frame: CGRect(x: 0, y: 0, width: width, height: height)
        )
        cameraView.setNeedsLayout()
        cameraView.layoutIfNeeded()
        return cameraView
    }
}
