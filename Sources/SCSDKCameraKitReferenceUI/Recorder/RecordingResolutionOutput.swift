//  Copyright Snap Inc. All rights reserved.

import CoreGraphics
import CoreMedia
import SCSDKCameraKit

/// Raises Camera Kit's processed output resolution without changing Lens viewport coordinates.
public final class RecordingResolutionOutput: NSObject, Output, OutputViewportProviding {
    public weak var delegate: OutputViewportProvidingDelegate?

    public var viewportSize: CGSize { .zero }
    public private(set) var outputResolution: CGSize = .zero
    public var safeArea: CGRect { .null }

    public func setOutputResolution(_ outputResolution: CGSize) {
        let compatibleSize = OutputSizeHelper.encoderCompatibleSize(outputResolution)
        guard compatibleSize != self.outputResolution else { return }
        self.outputResolution = compatibleSize
        delegate?.viewportChanged(self)
    }

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputTexture texture: Texture) {}

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {}

    public func cameraKit(_ cameraKit: CameraKitProtocol, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {}
}
