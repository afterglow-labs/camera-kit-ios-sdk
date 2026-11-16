import AVFoundation
import SCSDKCameraKit
@testable import SCSDKCameraKitReferenceUI

/// Camera Kit finishes creating and tearing down a session asynchronously, and dropping a session while
/// that work is in flight crashes inside the SDK binary. These controllers therefore live for the whole
/// test run instead of one per test.
enum SharedControllers {
    static let externalInput = RoutingTestInput()
    static let withExternalInput = CameraController(
        sessionConfig: SessionConfig(apiToken: "camera-kit-microphone-routing-test"),
        externalInput: externalInput,
        cameraPosition: .back
    )
    static let withBuiltInCamera = CameraController(
        sessionConfig: SessionConfig(apiToken: "camera-kit-microphone-routing-test"),
        cameraPosition: .back
    )
}

/// A caller-supplied camera input that the tests drive by hand.
final class RoutingTestInput: NSObject, Input {
    weak var destination: InputDestination?
    let horizontalFieldOfView: CGFloat = 70
    let frameSize = CGSize(width: 720, height: 1_280)
    private(set) var frameOrientation: AVCaptureVideoOrientation = .portrait
    var position: AVCaptureDevice.Position = .back
    private(set) var isRunning = false

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
