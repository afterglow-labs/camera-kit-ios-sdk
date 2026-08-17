//  Copyright Snap Inc. All rights reserved.
//  SCSDKCameraKitReferenceUI

import UIKit

public class CameraActionsView: UIView {
    // MARK: Views

    /// Button to flip camera input position
    public lazy var flipCameraButton: UIButton = {
        let button = UIButton(type: .custom)
        button.accessibilityIdentifier = CameraElements.flipCameraButton.id
        button.accessibilityValue = CameraElements.CameraFlip.front
        button.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_camera_flip_button", comment: "")
        button.setImage(
            UIImage(named: "ck_camera_flip", in: BundleHelper.resourcesBundle, compatibleWith: nil), for: .normal
        )
        button.translatesAutoresizingMaskIntoConstraints = false

        return button
    }()

    public lazy var flashToggleButtonBaseSelectedImage = UIImage(
        named: "ck_flash_on", in: BundleHelper.resourcesBundle, compatibleWith: nil
    )

    /// View with buttons to enable/disable flash and switch between system flash and ring light.
    public lazy var flashActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.toggleButton.accessibilityIdentifier = CameraElements.flashToggleButton.id
        view.toggleButton.accessibilityLabel = CameraKitLocalizedString(
            key: "camera_kit_flash_toggle_button",
            comment: ""
        )
        view.configurationButton.accessibilityIdentifier = CameraElements.flashConfigurationButton.id
        view.configurationButton.accessibilityLabel = CameraKitLocalizedString(
            key: "camera_kit_flash_configuration_button",
            comment: ""
        )
        if let image = flashToggleButtonBaseSelectedImage {
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20.0, color: .white), for: .selected)
        }
        view.toggleButton.setImage(
            UIImage(named: "ck_flash_off", in: BundleHelper.resourcesBundle, compatibleWith: nil),
            for: .normal
        )
        view.configurationButton.setImage(
            UIImage(named: "ck_adjustment_settings", in: BundleHelper.resourcesBundle, compatibleWith: nil),
            for: .normal
        )

        return view
    }()

    /// Sets up the flash toggle button for front flash.
    public func setupFlashToggleButtonForFront() {
        flashActionView.configurable = true
        flashActionView.toggleButton.setImage(
            flashToggleButtonBaseSelectedImage?.circleHighlightedImage(radius: 20), for: .selected
        )
    }

    /// Sets up the flash toggle button for back flash.
    public func setupFlashToggleButtonForBack() {
        flashActionView.configurable = false
        flashActionView.toggleButton.setImage(flashToggleButtonBaseSelectedImage, for: .selected)
    }

    /// View with buttons to enable/disable the tone map adjustment and control the intensity of the adjustment.
    public lazy var toneMapActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.toggleButton.accessibilityIdentifier = CameraElements.toneMapToggleButton.id
        view.toggleButton.accessibilityLabel = CameraKitLocalizedString(
            key: "camera_kit_tone_map_adjustment_toggle_button",
            comment: ""
        )
        view.configurationButton.accessibilityIdentifier = CameraElements.toneMapConfigurationButton.id
        view.configurationButton.accessibilityLabel = CameraKitLocalizedString(
            key:
            "camera_kit_tone_map_configuration_button",
            comment: ""
        )
        if let image = UIImage(named: "ck_tone_mode_on", in: BundleHelper.resourcesBundle, compatibleWith: nil) {
            view.toggleButton.setImage(image, for: .normal)
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20.0, color: .white), for: .selected)
        }
        view.configurationButton.setImage(
            UIImage(named: "ck_adjustment_settings", in: BundleHelper.resourcesBundle, compatibleWith: nil),
            for: .normal
        )

        return view
    }()

    /// View with buttons to enable/disable the portrait adjustment and control the intensity of the adjustment.
    public lazy var portraitActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.toggleButton.accessibilityLabel = CameraKitLocalizedString(
            key: "camera_kit_portrait_adjustment_toggle_button",
            comment: ""
        )
        view.toggleButton.accessibilityIdentifier = CameraElements.portraitToggleButton.id
        view.configurationButton.accessibilityLabel = CameraKitLocalizedString(
            key:
            "camera_kit_portrait_adjustment_configuration_button",
            comment: ""
        )
        view.configurationButton.accessibilityIdentifier = CameraElements.portraitConfigurationButton.id
        if let image = UIImage(named: "ck_portrait", in: BundleHelper.resourcesBundle, compatibleWith: nil) {
            view.toggleButton.setImage(image, for: .normal)
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20.0, color: .white), for: .selected)
        }
        view.configurationButton.setImage(
            UIImage(named: "ck_adjustment_settings", in: BundleHelper.resourcesBundle, compatibleWith: nil),
            for: .normal
        )

        return view
    }()

    /// Button to enable or disable Camera Kit's native high-definition Lens rendering path.
    public lazy var highDefinitionActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.configurable = false
        view.toggleButton.accessibilityIdentifier = CameraElements.highDefinitionToggleButton.id
        view.toggleButton.accessibilityLabel = CameraKitLocalizedString(
            key: "camera_kit_high_definition_rendering_toggle_button",
            comment: ""
        )
        view.toggleButton.setImage(Self.highDefinitionButtonImage(selected: false), for: .normal)
        view.toggleButton.setImage(Self.highDefinitionButtonImage(selected: true), for: .selected)
        return view
    }()

    /// Stack view used to arrange the view's buttons.
    public lazy var buttonStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            flipCameraButton, flashActionView, toneMapActionView, portraitActionView, highDefinitionActionView,
        ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.setCustomSpacing(6, after: flashActionView)
        stackView.setCustomSpacing(6, after: toneMapActionView)
        stackView.setCustomSpacing(6, after: portraitActionView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()

    // MARK: Recording Handling

    /// Views that were hidden via a call to `collapse` and should be unhidden in `expand`.
    private var viewsToRestore: Set<UIView>?

    /// Hide all camera actions except camera flip while recording.
    public func collapse() {
        viewsToRestore = []
        for subview in buttonStackView.arrangedSubviews[1...] where !subview.isHidden {
            viewsToRestore?.insert(subview)
            subview.alpha = 0
            subview.isHidden = true
        }
    }

    /// Unhide all camera actions that were hidden as a result of a call to `collapse`.
    public func expand() {
        for subview in buttonStackView.arrangedSubviews {
            if viewsToRestore?.contains(subview) ?? false {
                subview.alpha = 1
                subview.isHidden = false
            }
        }
        viewsToRestore = nil
    }

    // MARK: Init

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        for button in buttonStackView.arrangedSubviews.compactMap({ $0 as? UIButton }) {
            button.applyCameraActionButtonShadow()
        }
    }

    private static func highDefinitionButtonImage(selected: Bool) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { _ in
            if selected {
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            }

            let text = "HD" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: selected ? UIColor.black : UIColor.white,
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
    }
}

// MARK: View Setup

extension CameraActionsView {
    private func commonInit() {
        layer.cornerRadius = 20
        layer.masksToBounds = true
        backgroundColor = .black.withAlphaComponent(0.2)

        addSubview(buttonStackView)
        NSLayoutConstraint.activate([
            buttonStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStackView.topAnchor.constraint(equalTo: topAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        NSLayoutConstraint.activate([flipCameraButton.heightAnchor.constraint(equalToConstant: 40)])
    }
}
