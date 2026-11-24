//  Copyright Snap Inc. All rights reserved.

import AVFoundation
import AVKit
import SCSDKCameraKit
import UIKit

/// This is the default view that backs the CameraViewController.
open class CameraView: UIView {
    /// Direct capture-session preview displayed when processed Lens preview is disabled while recording.
    public let rawCameraPreviewView: RawCameraPreviewView = {
        let view = RawCameraPreviewView()
        view.isHidden = true
        return view
    }()

    /// default camerakit view to draw outputted textures
    public let previewView = PreviewView()

    /// Width-to-height ratio for the rendered Camera Kit viewport. Nil fills the camera view.
    public var previewAspectRatio: CGFloat? {
        didSet {
            if let previewAspectRatio, (!previewAspectRatio.isFinite || previewAspectRatio <= 0) {
                self.previewAspectRatio = nil
                return
            }
            setNeedsLayout()
        }
    }

    /// Height of host-app chrome drawn over the bottom of this view. The floating controls,
    /// capture row, and carousel sit directly above it, and Lens UI is kept clear of it.
    public var hostBottomInset: CGFloat = 0 {
        didSet {
            guard oldValue != hostBottomInset else { return }
            setNeedsLayout()
        }
    }

    public var hostTopInset: CGFloat = 0 {
        didSet { if oldValue != hostTopInset { setNeedsLayout() } }
    }

    public var toolbarAtTop = false {
        didSet {
            guard oldValue != toolbarAtTop else { return }
            updateCaptureDock()
            cameraActionsView.toolbarAtTop = toolbarAtTop
            setNeedsLayout()
        }
    }

    public var captureButtonsInToolbar = false {
        didSet {
            guard oldValue != captureButtonsInToolbar else { return }
            updateCaptureDock()
            setNeedsLayout()
        }
    }

    private let photoHousing = UIView()
    private let recordHousing = UIView()
    private let captureSpacer = UIView()
    private var captureRowWidthConstraint: NSLayoutConstraint?
    private var captureHousingSizeConstraints: [NSLayoutConstraint] = []

    private func updateCaptureDock() {
        NSLayoutConstraint.deactivate(bottomCaptureConstraints + topCaptureConstraints + screenTopCaptureConstraints)
        NSLayoutConstraint.activate(toolbarAtTop ? topCaptureConstraints + screenTopCaptureConstraints : bottomCaptureConstraints)
        captureRowWidthConstraint?.isActive = false
        captureSpacer.isHidden = true
        for (housing, stack) in [(photoHousing, cameraActionsView.buttonStackView), (recordHousing, cameraActionsView.lensButtonStackView)] {
            if let previousStack = housing.superview as? UIStackView {
                previousStack.removeArrangedSubview(housing)
            }
            housing.removeFromSuperview()
            if captureButtonsInToolbar {
                // The first row belongs to the expandable numbered lens group.
                stack.insertArrangedSubview(housing, at: toolbarAtTop ? 1 : stack.arrangedSubviews.count)
            } else {
                captureControlsView.addArrangedSubview(housing)
            }
        }
    }


    /// Outlines the safe area Camera Kit gives Lens UI, with its numbers, to diagnose Lens layout.
    public var showsLensSafeAreaOutline = false {
        didSet {
            lensSafeAreaOutlineTimer?.invalidate()
            lensSafeAreaOutlineTimer = nil
            lensSafeAreaOutlineView.isHidden = !showsLensSafeAreaOutline
            guard showsLensSafeAreaOutline else { return }
            addSubview(lensSafeAreaOutlineView)
            // Camera Kit recomputes the safe area on its own schedule, so poll while diagnosing.
            lensSafeAreaOutlineTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateLensSafeAreaOutline()
            }
        }
    }

    private var lensSafeAreaOutlineTimer: Timer?
    private let lensSafeAreaOutlineView: UILabel = {
        let label = UILabel()
        label.isUserInteractionEnabled = false
        label.layer.borderColor = UIColor.systemRed.cgColor
        label.layer.borderWidth = 2
        label.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private func updateLensSafeAreaOutline() {
        guard showsLensSafeAreaOutline else { return }
        let safeArea = previewView.safeArea
        lensSafeAreaOutlineView.frame = previewView.convert(safeArea, to: self)
        lensSafeAreaOutlineView.text = String(
            format: "Lens safe area\nx %.0f  y %.0f\nw %.0f  h %.0f\npreview %.0f x %.0f",
            safeArea.minX, safeArea.minY, safeArea.width, safeArea.height,
            previewView.bounds.width, previewView.bounds.height
        )
        bringSubviewToFront(lensSafeAreaOutlineView)
    }

    /// Distance from the top of this view to the top of the visible camera image. The Lens title
    /// appears just inside it, clear of the status bar, Dynamic Island, and any letterboxing.
    public var contentTopInset: CGFloat = 0 {
        didSet {
            guard oldValue != contentTopInset else { return }
            setNeedsLayout()
        }
    }

    // MARK: View properties

    /// bottom bar below carousel
    public let cameraBottomBar: CameraBottomBar = {
        let view = CameraBottomBar()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    public let hintLabel: UILabel = {
        let label = UILabel()
        label.alpha = 0.0
        label.font = .boldSystemFont(ofSize: 20.0)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    /// top label to show current selected lens
    public let lensLabel: UILabel = {
        let label = UILabel()
        label.alpha = 0
        label.accessibilityIdentifier = CameraElements.lensLabel.id
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    /// View used for ring light effect.
    public let ringLightView: RingLightView = {
        let view = RingLightView()
        view.accessibilityIdentifier = CameraElements.ringLightView.id
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// View that contains the buttons for various camera actions (flip, adjust, etc.)
    public let cameraActionsView: CameraActionsView = {
        let stackView = CameraActionsView()
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()

    private var cameraActionsBottomConstraint: NSLayoutConstraint?
    private var cameraActionsTopConstraint: NSLayoutConstraint?
    private var topCaptureConstraints: [NSLayoutConstraint] = []
    private var screenTopCaptureConstraints: [NSLayoutConstraint] = []
    private var captureControlsTopConstraint: NSLayoutConstraint?
    private var bottomCaptureConstraints: [NSLayoutConstraint] = []
    private let lensUITopOcclusionView = UIView()
    private var lensLabelTopConstraint: NSLayoutConstraint?
    private var lensTitleFadeWorkItem: DispatchWorkItem?
    private var carouselBottomConstraint: NSLayoutConstraint?
    private var carouselHeightConstraint: NSLayoutConstraint?
    private var carouselMaximumWidthConstraint: NSLayoutConstraint?
    private var carouselPreferredWidthConstraint: NSLayoutConstraint?
    private var photoButtonWidthConstraint: NSLayoutConstraint?
    private var photoButtonHeightConstraint: NSLayoutConstraint?
    private var videoButtonWidthConstraint: NSLayoutConstraint?
    private var videoButtonHeightConstraint: NSLayoutConstraint?
    private var captureControlsBottomConstraint: NSLayoutConstraint?
    private var captureControlsHeightConstraint: NSLayoutConstraint?
    private var attributionLeadingConstraint: NSLayoutConstraint?

    /// Control view for switching between flash and ring light as well as controlling ring light color and intensity.
    public lazy var flashControlView: FlashControlView = {
        let view = FlashControlView()
        view.accessibilityIdentifier = CameraElements.flashControl.id
        view.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_flash_control", comment: "")
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Label shown beneath the ring light control that provides a hint regarding dismissing the control.
    public let flashControlDismissalHint: UILabel = {
        let label = UILabel.controlDismissalHint()
        label.accessibilityIdentifier = CameraElements.flashControlDismissalHint.id
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    /// Control view for tone map adjustment that allows the user to adjust the intensity of the tone map effect.
    public let toneMapControlView: AdjustmentControlView = {
        let view = AdjustmentControlView()
        view.accessibilityIdentifier = CameraElements.toneMapControl.id
        view.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_tone_map_control", comment: "")
        let variant = AdjustmentControlView.Variant.tone
        view.tag = variant.rawValue
        view.primaryLabel.text = variant.label
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Label shown beneath the tone map control that provides a hint regarding dismissing the control.
    public let toneMapControlDismissalHintLabel: UILabel = {
        let label = UILabel.controlDismissalHint()
        label.accessibilityIdentifier = CameraElements.toneMapControlDismissalHint.id
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    /// Control view for portrait that allows the user to adjust the intensity of the portrait effect.
    public let portraitControlView: AdjustmentControlView = {
        let view = AdjustmentControlView()
        view.accessibilityIdentifier = CameraElements.portraitControl.id
        view.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_portrait_control", comment: "")
        let variant = AdjustmentControlView.Variant.portrait
        view.tag = variant.rawValue
        view.primaryLabel.text = variant.label
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Label shown beneath the portrait control that provides a hint regarding dismissing the control.
    public let portraitControlDismissalHintLabel: UILabel = {
        let label = UILabel.controlDismissalHint()
        label.accessibilityIdentifier = CameraElements.portraitControlDismissalHint.id
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    /// carousel to scroll through lenses
    public let carouselView: CarouselView = {
        let view = CarouselView()
        view.orientation = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Button for taking still photos.
    public let photoCaptureButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage(systemName: "camera.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        button.accessibilityLabel = "Take photo"
        button.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        button.layer.borderWidth = 2.0
        button.layer.cornerRadius = CameraCaptureChromeLayout.photoButtonDiameter / 2
        button.tintColor = .white
        button.setImage(image, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Button for starting and stopping video recording.
    public let videoCaptureButton: UIButton = {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = "Start recording"
        button.backgroundColor = UIColor(hex: 0xFF3447)
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        button.layer.borderWidth = 2.0
        button.layer.cornerRadius = CameraCaptureChromeLayout.videoButtonDiameter / 2
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Compact capture controls shown above the lens carousel.
    public let captureControlsView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = CameraCaptureChromeLayout.captureControlSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let lensUIBottomOcclusionView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// media picker to allow using photos from camera roll in lenses
    public lazy var mediaPickerView: MediaPickerView = {
        let view = MediaPickerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// message view to show updates when selected lens changes
    public let messageView: MessageNotificationView = {
        let view = MessageNotificationView()
        view.alpha = 0.0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    public let snapAttributionView: SnapAttributionView = {
        let view = SnapAttributionView()
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    public let activityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView()
        if #available(iOS 13, *) {
            view.style = .large
            view.color = .white
        } else {
            view.style = .whiteLarge
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Unimplemented")
    }

    override open func layoutSubviews() {
        updateChromeLayout()
        super.layoutSubviews()
        let previewFrame = resolvedPreviewFrame
        rawCameraPreviewView.frame = previewFrame
        previewView.frame = previewFrame
        updateLensUIBottomOcclusion()
        previewView.configureSafeArea(with: [lensUIBottomOcclusionView, lensUITopOcclusionView, lensLabel])
        ringLightView.ringLightGradient.updateIntensity(
            to: CGFloat(flashControlView.ringLightIntensityValue), animated: false
        )
    }

    private func updateChromeLayout() {
        let metrics = CameraCaptureChromeLayout.metrics(for: bounds.size)

        cameraActionsBottomConstraint?.constant = -max(hostBottomInset, safeAreaInsets.bottom)
        cameraActionsTopConstraint?.constant = toolbarAtTop ? max(hostTopInset, safeAreaInsets.top) : safeAreaInsets.top
        captureControlsView.distribution = .fill
        captureControlsTopConstraint?.constant = max(hostTopInset, safeAreaInsets.top)
            + metrics.bottomCarouselBottomGap + metrics.bottomCarouselHeight + metrics.captureControlsCarouselGap
        lensUITopOcclusionView.isHidden = !toolbarAtTop
        lensLabelTopConstraint?.constant = max(contentTopInset, safeAreaInsets.top) + metrics.lensLabelTopInset
        cameraActionsView.apply(scale: metrics.scale)

        carouselBottomConstraint?.constant = -max(hostBottomInset, safeAreaInsets.bottom) - metrics.bottomCarouselBottomGap
        carouselHeightConstraint?.constant = metrics.bottomCarouselHeight
        carouselMaximumWidthConstraint?.constant = metrics.bottomCarouselMaximumWidth
        carouselPreferredWidthConstraint?.constant = metrics.bottomCarouselMaximumWidth

        let photoDiameter = captureButtonsInToolbar ? 32 * metrics.scale : metrics.photoButtonDiameter
        let videoDiameter = captureButtonsInToolbar ? 32 * metrics.scale : metrics.videoButtonDiameter
        photoButtonWidthConstraint?.constant = photoDiameter
        photoButtonHeightConstraint?.constant = photoDiameter
        videoButtonWidthConstraint?.constant = videoDiameter
        videoButtonHeightConstraint?.constant = videoDiameter
        captureControlsBottomConstraint?.constant = -metrics.captureControlsCarouselGap
        captureControlsHeightConstraint?.constant = metrics.captureControlsHeight
        captureControlsView.spacing = captureButtonsInToolbar ? 0 : metrics.captureControlSpacing

        captureRowWidthConstraint?.constant = -108 * metrics.scale
        for constraint in captureHousingSizeConstraints {
            constraint.constant = captureButtonsInToolbar ? (constraint.firstAttribute == .height ? 24 : 8) * metrics.scale : 0
        }
        for housing in [photoHousing, recordHousing] {
            housing.backgroundColor = .clear
            housing.isHidden = captureControlsView.isHidden
            housing.alpha = captureControlsView.alpha
            housing.layer.borderColor = cameraActionsView.appearance.housingBorder?.cgColor
            housing.layer.borderWidth = 0
            housing.layer.cornerRadius = 8 * metrics.scale
            housing.layer.cornerCurve = .continuous
        }

        photoCaptureButton.layer.cornerRadius = photoDiameter / 2
        photoCaptureButton.layer.borderWidth = metrics.captureBorderWidth
        photoCaptureButton.setImage(
            UIImage(systemName: "camera.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: captureButtonsInToolbar ? 15 * metrics.scale : metrics.photoSymbolSize, weight: .semibold)
            ),
            for: .normal
        )
        videoCaptureButton.layer.cornerRadius = videoDiameter / 2
        videoCaptureButton.layer.borderWidth = metrics.captureBorderWidth
        if videoCaptureButton.image(for: .normal) != nil {
            videoCaptureButton.setImage(
                UIImage(systemName: "stop.fill")?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: metrics.recordingStopSymbolSize, weight: .bold)
                ),
                for: .normal
            )
        }

        attributionLeadingConstraint?.constant = metrics.attributionLeadingGap
        snapAttributionView.apply(metrics: metrics)
    }
}

// MARK: General View Setup

extension CameraView {
    private func setup() {
        setupPreview()
        setupRingLight()
        setupCameraBar()
        setupCameraActionsView()
        setupFlashButtons()
        setupToneMapButtons()
        setupPortraitButtons()
        setupHintLabel()
        setupLensLabel()
        setupCarousel()
        setupCaptureControls()
        setupLensUIBottomOcclusionView()
        setupMediaPicker()
        setupMessageView()
        setupSnapAttributionView()
        setupActivityIndicator()
        setupFlashControlView()
        setupFlashControlDismissalHint()
        setupToneMapControlView()
        setupToneMapControlDismissalHintLabel()
        setupPortraitControlView()
        setupPortraitControlDismissalLabel()
    }

    private func setupPreview() {
        backgroundColor = .black
        addSubview(rawCameraPreviewView)
        addSubview(previewView)
        rawCameraPreviewView.frame = bounds
        previewView.frame = bounds
        previewView.contentMode = .aspectFit
    }

    private var resolvedPreviewFrame: CGRect {
        guard
            let previewAspectRatio,
            previewAspectRatio.isFinite,
            previewAspectRatio > 0,
            bounds.width > 0,
            bounds.height > 0
        else {
            return bounds
        }

        let availableRatio = bounds.width / bounds.height
        let size: CGSize
        if availableRatio > previewAspectRatio {
            size = CGSize(width: bounds.height * previewAspectRatio, height: bounds.height)
        } else {
            size = CGSize(width: bounds.width, height: bounds.width / previewAspectRatio)
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }
}

// MARK: Ring Light

extension CameraView {
    private func setupRingLight() {
        addSubview(ringLightView)
        NSLayoutConstraint.activate([
            ringLightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            ringLightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ringLightView.topAnchor.constraint(equalTo: topAnchor),
            ringLightView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

// MARK: Camera Bottom Bar

extension CameraView {
    private func setupCameraBar() {
        addSubview(cameraBottomBar)
        NSLayoutConstraint.activate([
            cameraBottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            cameraBottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            cameraBottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            cameraBottomBar.heightAnchor.constraint(equalToConstant: 50.0),
        ])
    }
}

// MARK: Camera Actions View

extension CameraView {
    private func setupCameraActionsView() {
        addSubview(cameraActionsView)
        let bottomConstraint = cameraActionsView.bottomAnchor.constraint(equalTo: bottomAnchor)
        cameraActionsBottomConstraint = bottomConstraint
        let topConstraint = cameraActionsView.topAnchor.constraint(equalTo: topAnchor)
        cameraActionsTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            cameraActionsView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            cameraActionsView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            topConstraint,
            bottomConstraint,
        ])
    }
}

// MARK: Lens Label

extension CameraView {
    private func setupLensLabel() {
        addSubview(lensLabel)
        let topConstraint = lensLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        lensLabelTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            lensLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    /// Shows `text` in the hint label for a moment, then fades it out.
    public func showTransientHint(_ text: String) {
        hintLabel.text = text
        hintLabel.layer.removeAllAnimations()
        hintLabel.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.hintLabel.alpha = 1
        } completion: { finished in
            guard finished else { return }
            UIView.animate(withDuration: 0.4, delay: 2) {
                self.hintLabel.alpha = 0
            }
        }
    }

    /// Shows the Lens title when it changes, then fades it out like video-player overlay controls.
    public func showLensTitle(_ title: String?) {
        let title = title ?? ""
        guard title != lensLabel.text else { return }
        lensLabel.text = title
        lensTitleFadeWorkItem?.cancel()
        lensLabel.layer.removeAllAnimations()
        guard !title.isEmpty else {
            lensLabel.alpha = 0
            return
        }
        lensLabel.alpha = 1
        let fade = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: CameraCaptureChromeLayout.lensTitleFadeDuration) {
                self?.lensLabel.alpha = 0
            }
        }
        lensTitleFadeWorkItem = fade
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CameraCaptureChromeLayout.lensTitleVisibleDuration,
            execute: fade
        )
    }
}

// MARK: Carousel

extension CameraView {
    private func setupCarousel() {
        addSubview(carouselView)
        // Centered between the two side stacks, just above the host chrome.
        let bottomConstraint = carouselView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -8
        )
        let heightConstraint = carouselView.heightAnchor.constraint(equalToConstant: 48)
        let maximumWidthConstraint = carouselView.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        let preferredWidthConstraint = carouselView.widthAnchor.constraint(equalToConstant: 300)
        preferredWidthConstraint.priority = .defaultHigh
        carouselBottomConstraint = bottomConstraint
        carouselHeightConstraint = heightConstraint
        carouselMaximumWidthConstraint = maximumWidthConstraint
        carouselPreferredWidthConstraint = preferredWidthConstraint
        NSLayoutConstraint.activate([
            carouselView.centerXAnchor.constraint(equalTo: centerXAnchor),
            carouselView.leadingAnchor.constraint(
                greaterThanOrEqualTo: cameraActionsView.buttonStackView.trailingAnchor,
                constant: 6
            ),
            carouselView.trailingAnchor.constraint(
                lessThanOrEqualTo: cameraActionsView.lensButtonStackView.leadingAnchor,
                constant: -6
            ),
            bottomConstraint,
            heightConstraint,
            maximumWidthConstraint,
            preferredWidthConstraint,
        ])
    }
}

// MARK: Capture Controls

extension CameraView {
    private func setupCaptureControls() {
        for (housing, button) in [(photoHousing, photoCaptureButton), (recordHousing, videoCaptureButton)] {
            housing.translatesAutoresizingMaskIntoConstraints = false
            housing.addSubview(button)
            let width = housing.widthAnchor.constraint(equalTo: button.widthAnchor)
            let height = housing.heightAnchor.constraint(equalTo: button.heightAnchor)
            height.priority = .init(999)
            captureHousingSizeConstraints += [width, height]
            NSLayoutConstraint.activate([
                width, height,
                button.centerXAnchor.constraint(equalTo: housing.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: housing.centerYAnchor)
            ])
        }
        captureControlsView.addArrangedSubview(photoHousing)
        captureControlsView.addArrangedSubview(captureSpacer)
        captureControlsView.addArrangedSubview(recordHousing)
        captureSpacer.isHidden = true
        addSubview(captureControlsView)

        captureRowWidthConstraint = captureControlsView.widthAnchor.constraint(equalTo: widthAnchor, constant: -108)
        let photoWidthConstraint = photoCaptureButton.widthAnchor.constraint(equalToConstant: 34)
        let photoHeightConstraint = photoCaptureButton.heightAnchor.constraint(equalToConstant: 34)
        let videoWidthConstraint = videoCaptureButton.widthAnchor.constraint(equalToConstant: 38)
        let videoHeightConstraint = videoCaptureButton.heightAnchor.constraint(equalToConstant: 38)
        let bottomConstraint = captureControlsView.bottomAnchor.constraint(
            equalTo: carouselView.topAnchor,
            constant: -2
        )
        let heightConstraint = captureControlsView.heightAnchor.constraint(equalToConstant: 42)
        photoButtonWidthConstraint = photoWidthConstraint
        photoButtonHeightConstraint = photoHeightConstraint
        videoButtonWidthConstraint = videoWidthConstraint
        videoButtonHeightConstraint = videoHeightConstraint
        captureControlsBottomConstraint = bottomConstraint
        captureControlsHeightConstraint = heightConstraint
        let topConstraint = captureControlsView.topAnchor.constraint(equalTo: topAnchor)
        captureControlsTopConstraint = topConstraint
        screenTopCaptureConstraints = [topConstraint, captureControlsView.centerXAnchor.constraint(equalTo: centerXAnchor)]
        bottomCaptureConstraints = [
            bottomConstraint,
            captureControlsView.centerXAnchor.constraint(equalTo: centerXAnchor),
        ]

        NSLayoutConstraint.activate([
            photoWidthConstraint,
            photoHeightConstraint,
            videoWidthConstraint,
            videoHeightConstraint,
            heightConstraint,
        ] + bottomCaptureConstraints)
    }

    public func setVideoCaptureButtonRecording(_ isRecording: Bool) {
        videoCaptureButton.accessibilityLabel = isRecording ? "Stop recording" : "Start recording"
        videoCaptureButton.backgroundColor = UIColor(hex: 0xFF3447).withAlphaComponent(isRecording ? 0.72 : 1.0)
        let image = isRecording
            ? UIImage(systemName: "stop.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            : nil
        videoCaptureButton.setImage(image, for: .normal)
    }
}

// MARK: Lens UI Safe Area

extension CameraView {
    private func setupLensUIBottomOcclusionView() {
        lensUIBottomOcclusionView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(lensUIBottomOcclusionView)
        lensUITopOcclusionView.isUserInteractionEnabled = false
        addSubview(lensUITopOcclusionView)
    }

    /// Lenses may draw UI anywhere above the bottom controls, across the full width.
    private func updateLensUIBottomOcclusion() {
        cameraActionsView.layoutIfNeeded()
        let metrics = CameraCaptureChromeLayout.metrics(for: bounds.size)
        let controls: [UIView] = [
            cameraActionsView.buttonStackView,
            cameraActionsView.lensButtonStackView,
            captureControlsView,
            carouselView,
            snapAttributionView,
        ]
        let topControls: [UIView] = [cameraActionsView.buttonStackView, cameraActionsView.lensButtonStackView, captureControlsView]
        let topControlsBottom = topControls
            .filter { !$0.isHidden && $0.window != nil }
            .map { convert($0.bounds, from: $0).maxY }
            .max() ?? hostTopInset
        lensUITopOcclusionView.frame = CGRect(
            x: 0, y: 0, width: bounds.width,
            height: toolbarAtTop ? min(bounds.height, topControlsBottom + metrics.lensUIControlsClearance) : 0
        )
        let controlsTop = controls
            .filter { !$0.isHidden && $0.window != nil && (!toolbarAtTop || !topControls.contains($0)) }
            .map { convert($0.bounds, from: $0).minY }
            .min() ?? (bounds.maxY - max(hostBottomInset, safeAreaInsets.bottom))
        let top = max(bounds.minY, min(bounds.maxY, controlsTop - metrics.lensUIControlsClearance))
        lensUIBottomOcclusionView.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.maxY - top)
    }
}

// MARK: Media Picker

extension CameraView {
    private func setupMediaPicker() {
        addSubview(mediaPickerView)
        let bottomConstraint = mediaPickerView.bottomAnchor.constraint(equalTo: captureControlsView.topAnchor, constant: -4)
        let topConstraint = mediaPickerView.topAnchor.constraint(equalTo: cameraActionsView.topAnchor, constant: 4)
        bottomCaptureConstraints.append(bottomConstraint)
        topCaptureConstraints.append(topConstraint)
        NSLayoutConstraint.activate([
            bottomConstraint,
            mediaPickerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            mediaPickerView.widthAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.widthAnchor),
        ])
    }
}

// MARK: Messages

extension CameraView {
    private func setupMessageView() {
        addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.topAnchor.constraint(equalTo: lensLabel.bottomAnchor, constant: 8),
            messageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    public func showMessage(text: String, numberOfLines: Int, duration: TimeInterval = 1.5) {
        messageView.layer.removeAllAnimations()
        messageView.label.text = text
        messageView.label.numberOfLines = numberOfLines
        messageView.alpha = 0.0

        UIView.animate(
            withDuration: 0.5, delay: 0.0, options: .beginFromCurrentState,
            animations: {
                self.messageView.alpha = 1.0
            }, completion: nil
        )

        // Do a dispatch here instead of a completion/animation delay because UI tests get confused
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Ensure we're dismissing the initial message and not a subsequent one that was shown before dispatch fired
            guard self.messageView.label.text == text else { return }
            UIView.animate(
                withDuration: 0.5, delay: 0.0, options: .beginFromCurrentState,
                animations: {
                    self.messageView.alpha = 0.0
                }, completion: nil
            )
        }
    }
}

// MARK: Hint

extension CameraView {
    private func setupHintLabel() {
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

// MARK: Snap Attribution

extension CameraView {
    private func setupSnapAttributionView() {
        addSubview(snapAttributionView)
        let leadingConstraint = snapAttributionView.leadingAnchor.constraint(
            equalTo: captureControlsView.trailingAnchor,
            constant: 10
        )
        attributionLeadingConstraint = leadingConstraint
        NSLayoutConstraint.activate([
            leadingConstraint,
            snapAttributionView.bottomAnchor.constraint(equalTo: captureControlsView.bottomAnchor),
            snapAttributionView.trailingAnchor.constraint(
                lessThanOrEqualTo: cameraActionsView.lensButtonStackView.leadingAnchor,
                constant: -4
            ),
        ])
    }
}

// MARK: Activity Indicator

public extension CameraView {
    func setupActivityIndicator() {
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

// MARK: Flash

extension CameraView {
    private func setupFlashControlView() {
        addSubview(flashControlView)
        NSLayoutConstraint.activate([
            flashControlView.leadingAnchor.constraint(
                equalTo: cameraActionsView.flashActionView.toggleButton.trailingAnchor,
                constant: 8.0
            ),
            flashControlView.bottomAnchor.constraint(
                equalTo: cameraActionsView.flashActionView.toggleButton.bottomAnchor),
        ])
    }

    private func setupFlashControlDismissalHint() {
        addSubview(flashControlDismissalHint)
        NSLayoutConstraint.activate([
            flashControlDismissalHint.leadingAnchor.constraint(equalTo: flashControlView.leadingAnchor),
            flashControlDismissalHint.trailingAnchor.constraint(equalTo: flashControlView.trailingAnchor),
            flashControlDismissalHint.bottomAnchor.constraint(equalTo: flashControlView.topAnchor),
        ])
    }

    private func setupFlashButtons() {
        cameraActionsView.flashActionView.showActionSettings = { [weak self] in
            self?.hideAllControls()
            self?.flashControlView.isHidden = false
            self?.flashControlDismissalHint.isHidden = false
        }

        cameraActionsView.flashActionView.hideActionSettings = { [weak self] in
            self?.flashControlView.isHidden = true
            self?.flashControlDismissalHint.isHidden = true
        }

        cameraActionsView.flashActionView.toggleActionSettingsVisibility = { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.flashControlView.isHidden {
                strongSelf.hideAllControls()
            }
            strongSelf.flashControlView.isHidden.toggle()
            strongSelf.flashControlDismissalHint.isHidden.toggle()
        }
    }
}

// MARK: Tone Map

extension CameraView {
    private func setupToneMapControlView() {
        addSubview(toneMapControlView)
        NSLayoutConstraint.activate([
            toneMapControlView.leadingAnchor.constraint(
                equalTo: cameraActionsView.toneMapActionView.toggleButton.trailingAnchor, constant: 8.0
            ),
            toneMapControlView.bottomAnchor.constraint(
                equalTo: cameraActionsView.toneMapActionView.toggleButton.bottomAnchor),
        ])
    }

    private func setupToneMapControlDismissalHintLabel() {
        addSubview(toneMapControlDismissalHintLabel)
        NSLayoutConstraint.activate([
            toneMapControlDismissalHintLabel.leadingAnchor.constraint(equalTo: toneMapControlView.leadingAnchor),
            toneMapControlDismissalHintLabel.trailingAnchor.constraint(equalTo: toneMapControlView.trailingAnchor),
            toneMapControlDismissalHintLabel.bottomAnchor.constraint(equalTo: toneMapControlView.topAnchor),
        ])
    }

    private func setupToneMapButtons() {
        cameraActionsView.toneMapActionView.showActionSettings = { [weak self] in
            self?.hideAllControls()
            self?.toneMapControlView.isHidden = false
            self?.toneMapControlDismissalHintLabel.isHidden = false
        }

        cameraActionsView.toneMapActionView.hideActionSettings = { [weak self] in
            self?.toneMapControlView.isHidden = true
            self?.toneMapControlDismissalHintLabel.isHidden = true
        }

        cameraActionsView.toneMapActionView.toggleActionSettingsVisibility = { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.toneMapControlView.isHidden {
                strongSelf.hideAllControls()
            }
            strongSelf.toneMapControlView.isHidden.toggle()
            strongSelf.toneMapControlDismissalHintLabel.isHidden.toggle()
        }
    }
}

// MARK: Portrait

extension CameraView {
    private func setupPortraitControlView() {
        addSubview(portraitControlView)
        NSLayoutConstraint.activate([
            portraitControlView.leadingAnchor.constraint(
                equalTo: cameraActionsView.portraitActionView.toggleButton.trailingAnchor, constant: 8.0
            ),
            portraitControlView.bottomAnchor.constraint(
                equalTo: cameraActionsView.portraitActionView.toggleButton.bottomAnchor
            ),
        ])
    }

    private func setupPortraitControlDismissalLabel() {
        addSubview(portraitControlDismissalHintLabel)
        NSLayoutConstraint.activate([
            portraitControlDismissalHintLabel.leadingAnchor.constraint(equalTo: portraitControlView.leadingAnchor),
            portraitControlDismissalHintLabel.trailingAnchor.constraint(equalTo: portraitControlView.trailingAnchor),
            portraitControlDismissalHintLabel.bottomAnchor.constraint(equalTo: portraitControlView.topAnchor),
        ])
    }

    private func setupPortraitButtons() {
        cameraActionsView.portraitActionView.showActionSettings = { [weak self] in
            self?.hideAllControls()
            self?.portraitControlView.isHidden = false
            self?.portraitControlDismissalHintLabel.isHidden = false
        }

        cameraActionsView.portraitActionView.hideActionSettings = { [weak self] in
            self?.portraitControlView.isHidden = true
            self?.portraitControlDismissalHintLabel.isHidden = true
        }

        cameraActionsView.portraitActionView.toggleActionSettingsVisibility = { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.portraitControlView.isHidden {
                strongSelf.hideAllControls()
            }
            strongSelf.portraitControlView.isHidden.toggle()
            strongSelf.portraitControlDismissalHintLabel.isHidden.toggle()
        }
    }
}

// MARK: Camera Actions Control Helper

public extension CameraView {
    var isAnyControlVisible: Bool {
        ![
            flashControlView,
            flashControlDismissalHint,
            toneMapControlView,
            toneMapControlDismissalHintLabel,
            portraitControlView,
            portraitControlDismissalHintLabel,
        ].allSatisfy(\.isHidden)
    }

    func hideAllControls() {
        for view in [
            flashControlView,
            flashControlDismissalHint,
            toneMapControlView,
            toneMapControlDismissalHintLabel,
            portraitControlView,
            portraitControlDismissalHintLabel,
        ] {
            view.isHidden = true
        }
    }
}

// MARK: Tap to Focus

public extension CameraView {
    func drawTapAnimationView(at point: CGPoint) {
        let view = TapAnimationView(center: point)
        addSubview(view)

        view.show()
    }
}
