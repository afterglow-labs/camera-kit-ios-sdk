import UIKit

/// One camera-chrome coordinate system shared by the UIKit and SwiftUI reference UIs.
///
/// The unmodified design is expressed in iPhone 16 Pro logical points. Other
/// viewports apply one uniform scale so individual controls cannot drift apart.
public enum CameraCaptureChromeLayout {
    public static let iPhone16ProViewport = CGSize(width: 402, height: 874)

    public struct Metrics {
        public let scale: CGFloat

        public var photoButtonDiameter: CGFloat { 46.8 * scale }
        public var videoButtonDiameter: CGFloat { 52.2 * scale }
        public var captureControlSpacing: CGFloat { 18 * scale }
        public var captureControlsHeight: CGFloat { 64 * scale }
        public var captureControlsBottomClearance: CGFloat { 116 * scale }
        public var swiftUIFooterBottomPadding: CGFloat { 76 * scale }

        public var photoSymbolSize: CGFloat { 18.9 * scale }
        public var recordingStopSymbolSize: CGFloat { 14.4 * scale }
        public var captureBorderWidth: CGFloat { 2.7 * scale }

        public var attributionTopOffset: CGFloat { 118 * scale }
        public var attributionTrailingInset: CGFloat { 16 * scale }
        public var attributionFontSize: CGFloat { 9 * scale }
        public var attributionIconSize: CGFloat { 13 * scale }
        public var attributionSpacing: CGFloat { 3 * scale }

        public var cameraActionsTopInset: CGFloat { 6 * scale }
        public var cameraActionsTrailingInset: CGFloat { 8 * scale }
        public var cameraActionsWidth: CGFloat { 40 * scale }

        public var carouselWidth: CGFloat { 62 * scale }
        public var carouselTrailingInset: CGFloat { 10 * scale }
        public var carouselTopSpacing: CGFloat { 12 * scale }
        public var carouselBottomSpacing: CGFloat { 96 * scale }
        public var swiftUICarouselTopInset: CGFloat { 364 * scale }
        public var swiftUICarouselBottomInset: CGFloat { 132 * scale }

        // Bottom "U" layout: floating side stacks hug the screen edges and rest on the host's
        // bottom chrome, with the capture row and a horizontal Lens carousel between them.
        public var sideControlsEdgeInset: CGFloat { 2 * scale }
        public var sideControlsBottomGap: CGFloat { 4 * scale }
        public var sideControlsSpacing: CGFloat { 4 * scale }
        public var bottomCarouselHeight: CGFloat { 54 * scale }
        public var bottomCarouselBottomGap: CGFloat { 36 * scale }
        public var bottomCarouselMaximumWidth: CGFloat { 300 * scale }
        public var captureControlsCarouselGap: CGFloat { 28 * scale }
        public var attributionLeadingGap: CGFloat { 10 * scale }
        public var lensLabelTopInset: CGFloat { 6 * scale }
        /// Space kept between Lens UI and the topmost bottom control.
        public var lensUIControlsClearance: CGFloat { 8 * scale }
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
    public static let photoButtonDiameter: CGFloat = 46.8
    public static let videoButtonDiameter: CGFloat = 52.2
    public static let captureControlSpacing: CGFloat = 18
    public static let captureControlsHeight: CGFloat = 64
    public static let attributionFontSize: CGFloat = 9

    /// How long the Lens title stays up after a Lens change before fading out, and the fade length.
    public static let lensTitleVisibleDuration: TimeInterval = 2.5
    public static let lensTitleFadeDuration: TimeInterval = 0.4


    public static func trailingClearance(for viewportWidth: CGFloat) -> CGFloat {
        metrics(for: CGSize(width: viewportWidth, height: iPhone16ProViewport.height)).cameraActionsTrailingInset
    }
}
