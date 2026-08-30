import UIKit

/// One camera-chrome coordinate system shared by the UIKit and SwiftUI reference UIs.
///
/// The unmodified design is expressed in iPhone 16 Pro logical points. Other
/// viewports apply one uniform scale so individual controls cannot drift apart.
public enum CameraCaptureChromeLayout {
    public static let iPhone16ProViewport = CGSize(width: 402, height: 874)

    public struct Metrics {
        public let scale: CGFloat

        public var photoButtonDiameter: CGFloat { 52 * scale }
        public var videoButtonDiameter: CGFloat { 58 * scale }
        public var captureControlSpacing: CGFloat { 18 * scale }
        public var captureControlsHeight: CGFloat { 64 * scale }
        public var captureControlsBottomClearance: CGFloat { 116 * scale }
        public var swiftUIFooterBottomPadding: CGFloat { 76 * scale }

        public var photoSymbolSize: CGFloat { 21 * scale }
        public var recordingStopSymbolSize: CGFloat { 16 * scale }
        public var captureBorderWidth: CGFloat { 3 * scale }

        public var attributionTopOffset: CGFloat { 118 * scale }
        public var attributionTrailingInset: CGFloat { 16 * scale }
        public var attributionFontSize: CGFloat { 11 * scale }
        public var attributionIconSize: CGFloat { 16 * scale }
        public var attributionSpacing: CGFloat { 4 * scale }

        public var cameraActionsTopInset: CGFloat { 6 * scale }
        public var cameraActionsTrailingInset: CGFloat { 8 * scale }
        public var cameraActionsWidth: CGFloat { 40 * scale }

        public var carouselWidth: CGFloat { 62 * scale }
        public var carouselTrailingInset: CGFloat { 10 * scale }
        public var carouselTopSpacing: CGFloat { 12 * scale }
        public var carouselBottomSpacing: CGFloat { 96 * scale }
        public var swiftUICarouselTopInset: CGFloat { 364 * scale }
        public var swiftUICarouselBottomInset: CGFloat { 132 * scale }
    }

    public static func metrics(for viewport: CGSize) -> Metrics {
        guard viewport.width.isFinite,
              viewport.height.isFinite,
              viewport.width > 0,
              viewport.height > 0 else {
            return Metrics(scale: 1)
        }
        return Metrics(scale: min(
            viewport.width / iPhone16ProViewport.width,
            viewport.height / iPhone16ProViewport.height
        ))
    }

    // Baseline aliases retained for source compatibility with host apps.
    public static let photoButtonDiameter: CGFloat = 52
    public static let videoButtonDiameter: CGFloat = 58
    public static let captureControlSpacing: CGFloat = 18
    public static let captureControlsHeight: CGFloat = 64
    public static let attributionFontSize: CGFloat = 11

    public static func trailingClearance(for viewportWidth: CGFloat) -> CGFloat {
        metrics(for: CGSize(width: viewportWidth, height: iPhone16ProViewport.height)).cameraActionsTrailingInset
    }
}
