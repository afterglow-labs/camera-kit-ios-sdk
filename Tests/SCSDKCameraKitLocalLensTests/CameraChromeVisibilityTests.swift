import SCSDKCameraKit
import SwiftUI
import UIKit
import XCTest
@testable import SCSDKCameraKitReferenceSwiftUI
@testable import SCSDKCameraKitReferenceUI

@MainActor
final class CameraChromeVisibilityTests: XCTestCase {
    func testHiddenChromeKeepsEnabledRingLightVisible() {
        let controller = CameraController(
            sessionConfig: SessionConfig(apiToken: "camera-chrome-visibility-test")
        )
        let cameraView = SCSDKCameraKitReferenceSwiftUI.CameraView(
            cameraController: controller,
            chromeHidden: .constant(true),
            showsCaptureChrome: false,
            showsLensCarousel: false,
            showsCameraKitControls: false,
            showsChromeVisibilityButton: false
        )
        let host = UIHostingController(rootView: cameraView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        drainMainRunLoop()

        controller.setRingLightEnabled(true)
        drainMainRunLoop()

        guard let ringLight = firstSubview(of: RingLightView.self, in: host.view) else {
            return XCTFail("The SwiftUI preview did not render its ring-light effect")
        }
        XCTAssertFalse(hasHiddenAncestor(ringLight, through: host.view))
        XCTAssertGreaterThan(
            effectiveAlpha(of: ringLight, through: host.view),
            0.01,
            "Hiding camera chrome must not hide the enabled ring-light effect"
        )

        window.isHidden = true
    }

    private func firstSubview<T: UIView>(of type: T.Type, in root: UIView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func hasHiddenAncestor(_ view: UIView, through root: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden {
                return true
            }
            if candidate === root {
                return false
            }
            current = candidate.superview
        }
        return true
    }

    private func effectiveAlpha(of view: UIView, through root: UIView) -> CGFloat {
        var alpha: CGFloat = 1
        var current: UIView? = view
        while let candidate = current {
            alpha *= candidate.alpha
            if candidate === root {
                break
            }
            current = candidate.superview
        }
        return alpha
    }

    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}
