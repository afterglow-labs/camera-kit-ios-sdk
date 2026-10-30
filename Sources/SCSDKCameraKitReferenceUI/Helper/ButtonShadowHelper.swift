//  Copyright Snap Inc. All rights reserved.
//  SCSDKCameraKitReferenceUI

import UIKit

/// Helper to apply shadows to buttons.
public extension UIButton {
    /// Applies a shadow designed for camera action buttons.
    /// - Parameter outline: When set, a tight opaque halo in this color stands in for the drop
    ///   shadow and reads as an outline around dark icons.
    func applyCameraActionButtonShadow(scale: CGFloat = 1, outline: UIColor? = nil) {
        if let outline {
            layer.shadowColor = outline.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = scale
            layer.shadowOffset = .zero
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowRadius = 2 * scale
            layer.shadowOffset = CGSize(width: 0, height: scale)
        }
        // A second, tighter halo on the glyph itself firms the outline up.
        imageView?.layer.shadowColor = outline?.cgColor
        imageView?.layer.shadowOpacity = outline == nil ? 0 : 1
        imageView?.layer.shadowRadius = 0.6 * scale
        imageView?.layer.shadowOffset = .zero
    }
}
