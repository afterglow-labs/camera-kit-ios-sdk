//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// Snap attribution on Camera that contains "Powered by" and Snap ghost icon
public class SnapAttributionView: UIView {
    private enum Constants {
        static let snapGhostOutline = "ck_snap_ghost_outline"
    }

    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconSpacingConstraint: NSLayoutConstraint?

    public let poweredByLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = UIFont.sc_regularFont(size: CameraCaptureChromeLayout.attributionFontSize)
        label.textAlignment = .center
        label.text = CameraKitLocalizedString(key: "camera_kit_powered_by", comment: "")
        label.sizeToFit()
        label.isAccessibilityElement = false

        return label
    }()

    public let snapIconImage: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(
            named: Constants.snapGhostOutline,
            in: BundleHelper.resourcesBundle,
            compatibleWith: nil
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = false

        return imageView
    }()

    init() {
        super.init(frame: .zero)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isAccessibilityElement = true
        accessibilityIdentifier = CameraKitLocalizedString(key: "camera_kit_powered_by_snapchat", comment: "")

        addSubview(poweredByLabel)
        addSubview(snapIconImage)

        setupConstraints()
    }

    private func setupConstraints() {
        let baseline = CameraCaptureChromeLayout.metrics(
            for: CameraCaptureChromeLayout.iPhone16ProViewport
        )
        let iconWidthConstraint = snapIconImage.widthAnchor.constraint(
            equalToConstant: baseline.attributionIconSize
        )
        let iconHeightConstraint = snapIconImage.heightAnchor.constraint(
            equalToConstant: baseline.attributionIconSize
        )
        let iconSpacingConstraint = snapIconImage.leadingAnchor.constraint(
            equalTo: poweredByLabel.trailingAnchor,
            constant: baseline.attributionSpacing
        )
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        self.iconSpacingConstraint = iconSpacingConstraint

        NSLayoutConstraint.activate([
            poweredByLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            poweredByLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSpacingConstraint,
            snapIconImage.trailingAnchor.constraint(equalTo: trailingAnchor),
            snapIconImage.topAnchor.constraint(equalTo: topAnchor),
            snapIconImage.bottomAnchor.constraint(equalTo: bottomAnchor),
            snapIconImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,
        ])
    }

    public func apply(metrics: CameraCaptureChromeLayout.Metrics) {
        poweredByLabel.font = UIFont.sc_regularFont(size: metrics.attributionFontSize)
        iconWidthConstraint?.constant = metrics.attributionIconSize
        iconHeightConstraint?.constant = metrics.attributionIconSize
        iconSpacingConstraint?.constant = metrics.attributionSpacing
        invalidateIntrinsicContentSize()
    }
}
