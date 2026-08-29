import Foundation
import SCSDKCameraKit

/// Prevents Camera Kit's default exception handler from terminating the host app.
/// Camera Kit still closes the failed session before forwarding the exception here.
final class CameraKitLoggingErrorHandler: NSObject, ErrorHandler {
    static let shared = CameraKitLoggingErrorHandler()

    func handleError(_ error: NSException) {
        let reason = error.reason ?? "No reason supplied"
        NSLog("[CameraKit] Session stopped after %@: %@", error.name.rawValue, reason)
    }
}
