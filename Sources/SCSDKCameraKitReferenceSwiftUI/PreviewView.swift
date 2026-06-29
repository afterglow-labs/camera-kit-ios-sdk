//  Copyright Snap Inc. All rights reserved.

import SCSDKCameraKit
import SwiftUI
import UIKit

/// SwiftUI wrapper for the CameraKit preview view.
public struct PreviewView: UIViewRepresentable {
    private let cameraKit: CameraKitProtocol
    private let automaticallyConfiguresTouchHandler: Bool
    private let bottomSafeAreaInset: CGFloat

    /// Initializes a preview view and connects it to a CameraKit session as an output
    /// - Parameter cameraKit: the session to attach the preview view as an output to
    /// - Parameter automaticallyConfiguresTouchHandler: whether or not touch handling should automatically be configured for the view
    /// - Parameter bottomSafeAreaInset: the bottom area CameraKit lens UI should avoid.
    public init(
        cameraKit: CameraKitProtocol,
        automaticallyConfiguresTouchHandler: Bool = true,
        bottomSafeAreaInset: CGFloat = 0
    ) {
        self.cameraKit = cameraKit
        self.automaticallyConfiguresTouchHandler = automaticallyConfiguresTouchHandler
        self.bottomSafeAreaInset = bottomSafeAreaInset
    }

    public func makeUIView(context: Context) -> SafeAreaPreviewView {
        let inner = SafeAreaPreviewView()
        inner.automaticallyConfiguresTouchHandler = automaticallyConfiguresTouchHandler
        inner.bottomSafeAreaInset = bottomSafeAreaInset
        cameraKit.add(output: inner)
        return inner
    }

    public func updateUIView(_ uiView: SafeAreaPreviewView, context: Context) {
        uiView.bottomSafeAreaInset = bottomSafeAreaInset
    }
}

public final class SafeAreaPreviewView: SCSDKCameraKit.PreviewView {
    public var bottomSafeAreaInset: CGFloat = 0 {
        didSet {
            guard oldValue != bottomSafeAreaInset else { return }
            updateLensSafeAreaIfNeeded(force: true)
        }
    }

    private let bottomOcclusionView = UIView()
    private var lastConfiguredBounds: CGRect = .null
    private var lastConfiguredInset: CGFloat = -1

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupBottomOcclusionView()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Unimplemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateLensSafeAreaIfNeeded(force: false)
    }

    private func setupBottomOcclusionView() {
        bottomOcclusionView.backgroundColor = .clear
        bottomOcclusionView.isUserInteractionEnabled = false
        addSubview(bottomOcclusionView)
    }

    private func updateLensSafeAreaIfNeeded(force: Bool) {
        let inset = max(0, bottomSafeAreaInset)
        guard force || bounds != lastConfiguredBounds || inset != lastConfiguredInset else { return }

        lastConfiguredBounds = bounds
        lastConfiguredInset = inset

        if inset > 0, bounds.height > 0 {
            bottomOcclusionView.isHidden = false
            bottomOcclusionView.frame = CGRect(
                x: bounds.minX,
                y: max(bounds.minY, bounds.maxY - inset),
                width: bounds.width,
                height: min(inset, bounds.height)
            )
            configureSafeArea(with: [bottomOcclusionView])
        } else {
            bottomOcclusionView.isHidden = true
            configureSafeArea(with: [])
        }
    }
}
