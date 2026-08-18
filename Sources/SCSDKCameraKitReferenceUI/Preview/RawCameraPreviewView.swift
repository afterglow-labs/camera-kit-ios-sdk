//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import UIKit

/// A hardware-accelerated preview of the capture session before Camera Kit Lens rendering.
public final class RawCameraPreviewView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    public var videoOrientation: AVCaptureVideoOrientation = .portrait {
        didSet { updateConnection() }
    }

    /// Mirrors only this raw recording preview. It does not alter captured frames.
    public var isVideoMirrored = true {
        didSet { updateConnection() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Unimplemented")
    }

    public func connect(to captureSession: AVCaptureSession) {
        guard previewLayer.session !== captureSession else {
            updateConnection()
            return
        }
        previewLayer.session = captureSession
        updateConnection()
    }

    public func disconnect() {
        previewLayer.session = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateConnection()
    }

    private func updateConnection() {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isVideoMirrored
        }
    }
}
