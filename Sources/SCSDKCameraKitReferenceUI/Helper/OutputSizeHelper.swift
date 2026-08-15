//  Copyright Snap Inc. All rights reserved.
//  SCSDKCameraKitReferenceUI

import AVFoundation
import Foundation

/// Provides helper functions to determine output sizes given input sizes and other constraints (aspect ratio, orientation, etc.)
public enum OutputSizeHelper {
    /// Returns the size normalized to a new aspect ratio and orientation.
    /// For example, given an input size of 1080x1920 and aspect ratio of 0.462 and portrait orientation,
    /// this will return a new size of 887x1920.
    /// - Parameters:
    ///   - size: The original input size to normalize.
    ///   - aspectRatio: The aspect ratio to normalize the output size to.
    ///   - orientation: The orientation of the input size (defaults to portrait).
    /// - Returns: The new size normalized to the aspect ratio.
    public static func normalizedSize(
        for size: CGSize, aspectRatio: CGFloat, orientation: AVCaptureVideoOrientation = .portrait
    ) -> CGSize {
        var height = orientation == .portrait ? size.height : size.width
        var width = orientation == .portrait ? size.width : size.height

        if orientation == .landscapeLeft || orientation == .landscapeRight {
            if height > width * aspectRatio {
                height = width * aspectRatio
            } else {
                width = height / aspectRatio
            }
        } else {
            if width > height * aspectRatio {
                width = height * aspectRatio
            } else {
                height = width / aspectRatio
            }
        }

        return encoderCompatibleSize(CGSize(width: width, height: height))
    }

    /// Returns positive, even pixel dimensions accepted by the video encoder.
    public static func encoderCompatibleSize(_ size: CGSize) -> CGSize {
        func compatibleDimension(_ value: CGFloat) -> CGFloat {
            guard value.isFinite, value > 0 else { return 0 }
            return max(2, floor(value / 2) * 2)
        }

        return CGSize(
            width: compatibleDimension(size.width),
            height: compatibleDimension(size.height)
        )
    }
}
