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
}
