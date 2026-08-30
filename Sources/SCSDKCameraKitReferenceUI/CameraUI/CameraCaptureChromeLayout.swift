import UIKit

/// One camera-chrome coordinate system shared by the UIKit and SwiftUI reference UIs.
///
/// The unmodified design is expressed in iPhone 16 Pro logical points. Other
/// viewports apply one uniform scale so individual controls cannot drift apart.
public enum CameraCaptureChromeLayout {
    public static let iPhone16ProViewport = CGSize(width: 402, height: 874)

    public struct Metrics {
        public let scale: CGFloat

        public var photoButtonDiameter: CGFloat { 34 * scale }
        public var videoButtonDiameter: CGFloat { 38 * scale }
        public var captureControlSpacing: CGFloat { 18 * scale }
        public var captureControlsHeight: CGFloat { 42 * scale }
        public var captureControlsTopOffset: CGFloat { 70 * scale }
        public var swiftUIFooterBottomPadding: CGFloat { 38 * scale }

        public var photoSymbolSize: CGFloat { 15 * scale }
        public var recordingStopSymbolSize: CGFloat { 12 * scale }
        public var captureBorderWidth: CGFloat { 2 * scale }

        public var attributionTopOffset: CGFloat { 118 * scale }
        public var attributionTrailingInset: CGFloat { 16 * scale }
        public var attributionFontSize: CGFloat { 12 * scale }
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
    public static let photoButtonDiameter: CGFloat = 34
    public static let videoButtonDiameter: CGFloat = 38
    public static let captureControlSpacing: CGFloat = 18
    public static let captureControlsHeight: CGFloat = 42
    public static let attributionFontSize: CGFloat = 12

    public static func trailingClearance(for viewportWidth: CGFloat) -> CGFloat {
        metrics(for: CGSize(width: viewportWidth, height: iPhone16ProViewport.height)).cameraActionsTrailingInset
    }
}
