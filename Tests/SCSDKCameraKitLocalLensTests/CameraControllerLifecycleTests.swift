import AVFoundation
import SCSDKCameraKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class CameraControllerLifecycleTests: XCTestCase {
    func testRefreshingInputAttributesBeforeCameraKitStartsDoesNotCrash() {
        let config = SessionConfig(apiToken: "camera-kit-lifecycle-test")
        let controller = CameraController(sessionConfig: config)

        XCTAssertFalse(controller.captureSession.isRunning)
        controller.refreshActiveInputAttributes()
    }

    func testExternalInputKeepsItsPositionAndDisablesDeviceControls() {
        let input = TestExternalInput(position: .back)
        let config = SessionConfig(apiToken: "camera-kit-external-input-test")
        let controller = CameraController(
            sessionConfig: config,
            externalInput: input,
            cameraPosition: .back
        )

        XCTAssertTrue(controller.usesExternalInput)
        XCTAssertFalse(controller.supportsCameraDeviceControls)
        XCTAssertEqual(controller.cameraPosition, .back)

        controller.flipCamera()

        XCTAssertEqual(controller.cameraPosition, .back)
    }
}

private final class TestExternalInput: NSObject, Input {
    weak var destination: InputDestination?
    let horizontalFieldOfView: CGFloat = 70
    let frameSize = CGSize(width: 720, height: 1_280)
    private(set) var frameOrientation: AVCaptureVideoOrientation = .portrait
    var position: AVCaptureDevice.Position
    private(set) var isRunning = false

    init(position: AVCaptureDevice.Position) {
        self.position = position
    }

    func startRunning() {
        isRunning = true
    }

    func stopRunning() {
        isRunning = false
    }

    func setVideoOrientation(_ videoOrientation: AVCaptureVideoOrientation) {
        frameOrientation = videoOrientation
    }
}
