import UIKit

public enum CameraCaptureChromeLayout {
    public static let captureControlsBottomClearance: CGFloat = 116
    public static let attributionBottomClearance: CGFloat = 108
    public static let lensStatusTopClearance: CGFloat = 72

    public static let photoButtonDiameter: CGFloat = 52
    public static let videoButtonDiameter: CGFloat = 58
    public static let captureControlSpacing: CGFloat = 18
    public static let captureControlsCenterOffset = -(photoButtonDiameter + captureControlSpacing) / 2
    public static let captureControlsHeight: CGFloat = 64
    public static let attributionFontSize: CGFloat = 11

    /// Keeps right-edge camera chrome clear of compact device edges and display clipping.
    public static func trailingClearance(for viewportWidth: CGFloat) -> CGFloat {
        if viewportWidth < 390 {
            return 28
        }
        if viewportWidth < 430 {
            return 24
        }
        return 20
    }
}
