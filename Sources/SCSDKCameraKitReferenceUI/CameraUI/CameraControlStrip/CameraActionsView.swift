//  Copyright Snap Inc. All rights reserved.
//  SCSDKCameraKitReferenceUI

import UIKit

/// Floating camera controls laid out as two bottom stacks: camera settings hugging the leading
/// edge and Lens toggles hugging the trailing edge. The view itself is transparent and passes
/// touches through everywhere except on its buttons.
public class CameraActionsView: UIView {
    private var layoutScale: CGFloat = 1
    private var flipCameraHeightConstraint: NSLayoutConstraint?
    private var stackEdgeConstraints: [NSLayoutConstraint] = []
    private var stackBottomConstraints: [NSLayoutConstraint] = []
    private var stackWidthConstraints: [NSLayoutConstraint] = []

    /// Horizontal clearance for the Lens Controls strip at the supplied safe-area width.
    public static func adaptiveTrailingInset(forAvailableWidth width: CGFloat) -> CGFloat {
        CameraCaptureChromeLayout.trailingClearance(for: width)
    }

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
        applyIconTint()
    }

    /// Sets up the flash toggle button for back flash.
    public func setupFlashToggleButtonForBack() {
        flashActionView.configurable = false
        flashActionView.toggleButton.setImage(flashToggleButtonBaseSelectedImage, for: .selected)
        applyIconTint()
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

    /// Button to enable or disable the host-provided persistent Retouch Lens layer.
    public lazy var retouchActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.configurable = true
        view.toggleButton.accessibilityIdentifier = CameraElements.retouchToggleButton.id
        view.toggleButton.accessibilityLabel = "Retouch"
        view.toggleButton.tintColor = .white
        if let image = UIImage(
            systemName: "wand.and.stars",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        ) {
            view.toggleButton.setImage(image, for: .normal)
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20, color: .white), for: .selected)
        }
        view.configurationButton.tintColor = .white
        view.configurationButton.accessibilityLabel = "Retouch Style"
        view.configurationButton.setImage(
            UIImage(
                systemName: "slider.horizontal.3",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            ),
            for: .normal
        )
        return view
    }()

    /// Button to enable or disable the host-provided persistent Nose Adjustments Lens layer.
    public lazy var noseAdjustmentsActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.configurable = true
        view.toggleButton.accessibilityIdentifier = CameraElements.noseAdjustmentsToggleButton.id
        view.toggleButton.accessibilityLabel = "Nose Adjustments"
        view.toggleButton.tintColor = .white
        if let image = UIImage(
            systemName: "face.smiling",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        ) {
            view.toggleButton.setImage(image, for: .normal)
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20, color: .white), for: .selected)
        }
        view.configurationButton.tintColor = .white
        view.configurationButton.accessibilityLabel = "Edit Nose"
        view.configurationButton.setImage(
            UIImage(
                systemName: "slider.horizontal.3",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            ),
            for: .normal
        )
        return view
    }()

    /// Customizable Lens slot 1, a persistent Lens layer the user assigns.
    public lazy var lensSlotOneActionView = Self.lensSlotActionView(
        number: 1,
        identifier: CameraElements.lensSlotOneToggleButton.id
    )

    /// Customizable Lens slot 2, a persistent Lens layer the user assigns.
    public lazy var lensSlotTwoActionView = Self.lensSlotActionView(
        number: 2,
        identifier: CameraElements.lensSlotTwoToggleButton.id
    )

    /// Customizable Lens slot 3, a persistent Lens layer the user assigns.
    public lazy var lensSlotThreeActionView = Self.lensSlotActionView(
        number: 3,
        identifier: CameraElements.lensSlotThreeToggleButton.id
    )

    /// Customizable Lens slot 4, a persistent Lens layer the user assigns.
    public lazy var lensSlotFourActionView = Self.lensSlotActionView(
        number: 4,
        identifier: CameraElements.lensSlotFourToggleButton.id
    )

    public lazy var lensSlotFiveActionView = Self.lensSlotActionView(
        number: 5,
        identifier: CameraElements.lensSlotFiveToggleButton.id
    )

    public lazy var lensSlotSixActionView = Self.lensSlotActionView(
        number: 6,
        identifier: CameraElements.lensSlotSixToggleButton.id
    )

    public lazy var lensSlotSevenActionView = Self.lensSlotActionView(
        number: 7,
        identifier: CameraElements.lensSlotSevenToggleButton.id
    )

    public lazy var lensSlotEightActionView = Self.lensSlotActionView(
        number: 8,
        identifier: CameraElements.lensSlotEightToggleButton.id
    )

    private lazy var extraSlots = (9...20).map {
        Self.lensSlotActionView(number: $0, identifier: "LensSlot\($0)ToggleButton")
    }
    private lazy var rightGroup = makeGroup(1...10)
    private lazy var leftGroup = makeGroup(11...20)
    private func makeGroup(_ range: ClosedRange<Int>) -> CameraConfigurableActionView {
        let view = CameraConfigurableActionView()
        let label = "\(range.lowerBound)–\(range.upperBound)"
        let button = view.toggleButton
        button.setTitle(label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.accessibilityLabel = "Lens buttons " + label
        button.accessibilityIdentifier = "lensSlots\(range.lowerBound)To\(range.upperBound)"
        button.accessibilityValue = "Collapsed"
        view.enableAction = { [weak button] in button?.accessibilityValue = "Expanded" }
        view.disableAction = { [weak button] in button?.accessibilityValue = "Collapsed" }

        let slots = lensButtonActionViews
        let column = UIStackView(arrangedSubviews: range.map { slots[$0 - 1] })
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        // Show the entire column when it fits. If other controls need the space,
        // only the numbered buttons scroll, so the group toggle stays reachable.
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.scrollsToTop = false
        scroll.addSubview(column)
        let content = scroll.contentLayoutGuide
        let viewport = scroll.frameLayoutGuide
        let fullHeight = viewport.heightAnchor.constraint(equalTo: column.heightAnchor)
        fullHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.widthAnchor.constraint(equalTo: viewport.widthAnchor),
            fullHeight,
        ])
        view.setExpansionContent(scroll)
        return view
    }

    /// Mutes or unmutes sound from Lenses. The microphone is unaffected.
    public lazy var lensAudioActionView: CameraConfigurableActionView = {
        let view = CameraConfigurableActionView()
        view.configurable = false
        view.toggleButton.accessibilityIdentifier = CameraElements.lensAudioToggleButton.id
        view.toggleButton.accessibilityLabel = "Mute Lens Audio"
        view.toggleButton.tintColor = .white
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        if let sound = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: configuration) {
            view.toggleButton.setImage(sound, for: .normal)
        }
        if let muted = UIImage(systemName: "speaker.slash.fill", withConfiguration: configuration) {
            view.toggleButton.setImage(muted.circleHighlightedImage(radius: 20, color: .white), for: .selected)
        }
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
        view.toggleButton.setImage(Self.highDefinitionButtonImage(selected: false, tint: .white, outline: nil), for: .normal)
        view.toggleButton.setImage(Self.highDefinitionButtonImage(selected: true, tint: .white, outline: nil), for: .selected)
        return view
    }()

    /// Camera settings stack (flip, flash, tone, portrait, HD), floating at the bottom leading edge.
    public lazy var buttonStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            flipCameraButton, flashActionView, toneMapActionView, portraitActionView, highDefinitionActionView, leftGroup,
        ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.setCustomSpacing(6, after: flashActionView)
        stackView.setCustomSpacing(6, after: toneMapActionView)
        stackView.setCustomSpacing(6, after: portraitActionView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()

    /// Lens toggle stack (Retouch, Nose Adjustments, Lens slot group, Lens audio), floating at the
    /// bottom trailing edge.
    public lazy var lensButtonStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            retouchActionView, noseAdjustmentsActionView,
            rightGroup,
            lensAudioActionView,
        ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.setCustomSpacing(6, after: retouchActionView)
        stackView.setCustomSpacing(6, after: noseAdjustmentsActionView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()

    /// How the side stacks are drawn on a host's themed chrome.
    public struct Appearance: Equatable {
        /// Fill of the frosted housing behind each stack, rising from the host's bottom chrome; nil draws none.
        public var housingTint: UIColor?
        /// Hairline along the housing's edges.
        public var housingBorder: UIColor?
        /// Color of every icon in both stacks.
        public var iconTint: UIColor
        /// Color of a switched-on action's circle.
        public var selectedIconTint: UIColor
        /// Outline around the icons in place of their drop shadow, for dark icons; nil keeps the shadow.
        public var iconOutline: UIColor?

        public static let standard = Appearance(housingTint: nil, housingBorder: nil, iconTint: .white)

        public init(
            housingTint: UIColor?,
            housingBorder: UIColor?,
            iconTint: UIColor,
            selectedIconTint: UIColor? = nil,
            iconOutline: UIColor? = nil
        ) {
            self.housingTint = housingTint
            self.housingBorder = housingBorder
            self.iconTint = iconTint
            self.selectedIconTint = selectedIconTint ?? iconTint
            self.iconOutline = iconOutline
        }
    }

    public var appearance = Appearance.standard {
        didSet {
            guard appearance != oldValue else { return }
            for housing in [buttonStackHousingView, lensButtonStackHousingView] {
                Self.style(housing, tint: appearance.housingTint, border: appearance.housingBorder)
            }
            applyIconTint()
            setNeedsLayout()
        }
    }

    /// Colors every stack icon from `appearance`: icons in `iconTint`, a switched-on action's circle in
    /// `selectedIconTint`, and HD's drawn text redrawn to match. Colors are baked into each image so
    /// the two states can differ.
    private func applyIconTint() {
        let actionViews = [
            flashActionView, toneMapActionView, portraitActionView, retouchActionView,
            noseAdjustmentsActionView, lensAudioActionView, rightGroup, leftGroup,
        ] + lensButtonActionViews
        for group in [rightGroup, leftGroup] {
            group.toggleButton.setTitleColor(appearance.iconTint, for: .normal)
            group.toggleButton.setTitleColor(appearance.selectedIconTint, for: .selected)
        }
        for button in [flipCameraButton] + actionViews.flatMap({ [$0.toggleButton, $0.configurationButton] }) {
            button.tintColor = appearance.iconTint
            for (state, color) in [(UIControl.State.normal, appearance.iconTint), (.selected, appearance.selectedIconTint)] {
                if let image = button.image(for: state) {
                    button.setImage(
                        image.withRenderingMode(.alwaysTemplate).withTintColor(color, renderingMode: .alwaysOriginal),
                        for: state
                    )
                }
            }
        }
        for actionView in actionViews + [highDefinitionActionView] {
            actionView.iconOutline = appearance.iconOutline
        }
        highDefinitionActionView.toggleButton.setImage(
            Self.highDefinitionButtonImage(selected: false, tint: appearance.iconTint, outline: appearance.iconOutline),
            for: .normal
        )
        highDefinitionActionView.toggleButton.setImage(
            Self.highDefinitionButtonImage(selected: true, tint: appearance.selectedIconTint, outline: nil),
            for: .selected
        )
        setNeedsLayout()
    }

    /// Anchor both side stacks to the host toolbar's edge.
    public var toolbarAtTop = false {
        didSet {
            guard oldValue != toolbarAtTop else { return }
            NSLayoutConstraint.deactivate(toolbarAtTop ? bottomDockConstraints : topDockConstraints)
            NSLayoutConstraint.activate(toolbarAtTop ? topDockConstraints : bottomDockConstraints)
            setNeedsLayout()
        }
    }

    private var topDockConstraints: [NSLayoutConstraint] = []
    private var bottomDockConstraints: [NSLayoutConstraint] = []
    private var stackTopConstraints: [NSLayoutConstraint] = []
    private let buttonStackHousingView = UIVisualEffectView()
    private let lensButtonStackHousingView = UIVisualEffectView()
    private var housingOverhangConstraints: [NSLayoutConstraint] = []
    private var housingPaddingConstraints: [NSLayoutConstraint] = []

    /// Match the host chrome's theme color on both side toolbars.
    private static func style(_ housing: UIVisualEffectView, tint: UIColor?, border: UIColor?) {
        housing.effect = nil
        housing.contentView.backgroundColor = tint
        housing.layer.borderWidth = 0
        let outline = (housing.layer.sublayers?.first { $0.name == "openHousingOutline" } as? CAShapeLayer)
            ?? CAShapeLayer()
        outline.name = "openHousingOutline"
        outline.fillColor = UIColor.clear.cgColor
        outline.strokeColor = border?.cgColor
        outline.lineWidth = border == nil ? 0 : 1
        if outline.superlayer == nil {
            housing.layer.addSublayer(outline)
        }
        housing.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        housing.clipsToBounds = true
    }

    // MARK: Recording Handling

    /// Views that were hidden via a call to `collapse` and should be unhidden in `expand`.
    private var viewsToRestore: Set<UIView>?

    /// Hide all camera actions except camera flip while recording.
    public func collapse() {
        guard viewsToRestore == nil else { return }
        for group in [rightGroup, leftGroup] {
            group.toggleButton.isSelected = false
            group.collapse()
            group.disableAction?()
        }
        viewsToRestore = []
        let collapsible = Array(buttonStackView.arrangedSubviews.dropFirst()) + lensButtonStackView.arrangedSubviews
        for subview in collapsible where !subview.isHidden {
            viewsToRestore?.insert(subview)
            subview.alpha = 0
            subview.isHidden = true
        }
    }

    /// Unhide all camera actions that were hidden as a result of a call to `collapse`.
    public func expand() {
        for subview in buttonStackView.arrangedSubviews + lensButtonStackView.arrangedSubviews {
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
            button.applyCameraActionButtonShadow(scale: layoutScale, outline: appearance.iconOutline)
        }
        // No housing behind a stack whose buttons are all hidden (e.g. while recording).
        for (housing, stack) in [
            (buttonStackHousingView, buttonStackView),
            (lensButtonStackHousingView, lensButtonStackView),
        ] {
            housing.isHidden = appearance.housingTint == nil || stack.arrangedSubviews.allSatisfy(\.isHidden)
            // Leave the bottom open where this housing joins the host's bottom toolbar.
            if let outline = housing.layer.sublayers?.first(where: { $0.name == "openHousingOutline" }) as? CAShapeLayer {
                outline.frame = housing.bounds
                let rect = housing.bounds.insetBy(dx: 0.5, dy: 0.5)
                let radius = min(housing.layer.cornerRadius, rect.width / 2, rect.height / 2)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.minX, y: housing.bounds.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
                path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                                  controlPoint: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                                  controlPoint: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: housing.bounds.maxY))
                if toolbarAtTop {
                    path.apply(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: housing.bounds.height))
                }
                housing.layer.maskedCorners = toolbarAtTop
                    ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                    : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                outline.path = path.cgPath
            }
        }
    }

    /// Only the buttons take touches; everything else falls through to the camera preview.
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self || view === buttonStackView || view === lensButtonStackView ? nil : view
    }

    /// Applies the single camera-chrome scale to the complete action strip.
    public func apply(scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        layoutScale = scale
        let metrics = CameraCaptureChromeLayout.Metrics(scale: scale)
        buttonStackView.spacing = metrics.sideControlsSpacing
        buttonStackView.setCustomSpacing(6 * scale, after: flashActionView)
        buttonStackView.setCustomSpacing(6 * scale, after: toneMapActionView)
        buttonStackView.setCustomSpacing(6 * scale, after: portraitActionView)
        lensButtonStackView.spacing = metrics.sideControlsSpacing
        lensButtonStackView.setCustomSpacing(6 * scale, after: retouchActionView)
        lensButtonStackView.setCustomSpacing(6 * scale, after: noseAdjustmentsActionView)

        stackEdgeConstraints.forEach { $0.constant = $0.firstAttribute == .leading
            ? metrics.sideControlsEdgeInset : -metrics.sideControlsEdgeInset }
        stackBottomConstraints.forEach { $0.constant = -metrics.sideControlsBottomGap }
        stackTopConstraints.forEach { $0.constant = metrics.sideControlsBottomGap }
        stackWidthConstraints.forEach { $0.constant = 40 * scale }
        housingOverhangConstraints.forEach { $0.constant = ($0.constant < 0 ? -32 : 32) * scale }
        buttonStackHousingView.layer.cornerRadius = 8 * scale
        lensButtonStackHousingView.layer.cornerRadius = 8 * scale
        housingPaddingConstraints.forEach { $0.constant = ($0.constant < 0 ? -6 : 6) * scale }
        flipCameraHeightConstraint?.constant = 40 * scale
        flipCameraButton.imageView?.transform = CGAffineTransform(scaleX: scale, y: scale)
        for actionView in [
            flashActionView,
            toneMapActionView,
            portraitActionView,
            retouchActionView,
            noseAdjustmentsActionView,
            leftGroup, rightGroup, lensAudioActionView, highDefinitionActionView,
        ] + lensButtonActionViews {
            actionView.apply(scale: scale)
        }
    }

    // MARK: Customizable Lens Buttons

    /// Shown when an empty customizable Lens button is tapped.
    public static let emptyLensButtonHint = "Assign a Lens in Settings ▸ Lenses, or hold the search button."

    private var lensButtonActionViews: [CameraConfigurableActionView] {
        [lensSlotOneActionView, lensSlotTwoActionView, lensSlotThreeActionView, lensSlotFourActionView, lensSlotFiveActionView, lensSlotSixActionView, lensSlotSevenActionView, lensSlotEightActionView] + extraSlots
    }

    /// Connects buttons 1 through 20 and the Lens audio button to `controller`. Lens buttons switch their
    /// assigned Lens layer on or off, and an empty one shows `emptyLensButtonHint` through `showHint`.
    public func connectLensButtons(to controller: CameraController, showHint: @escaping (String) -> Void) {
        lensAudioActionView.enableAction = { [weak controller] in
            controller?.setLensAudioMuted(true)
        }
        lensAudioActionView.disableAction = { [weak controller] in
            controller?.setLensAudioMuted(false)
        }
        for (index, action) in lensButtonActionViews.enumerated() {
            action.enableAction = { [weak controller, weak action] in
                guard let controller else { return }
                guard controller.isLensButtonAvailable(at: index) else {
                    action?.toggleButton.isSelected = false
                    showHint(Self.emptyLensButtonHint)
                    return
                }
                controller.setLensButtonEnabled(true, at: index)
            }
            action.disableAction = { [weak controller] in
                controller?.setLensButtonEnabled(false, at: index)
            }
        }
        syncLensButtons(with: controller)
    }

    /// Shows each button's on/off state (an empty button is dimmed) and whether Lens audio is muted.
    public func syncLensButtons(with controller: CameraController) {
        lensAudioActionView.toggleButton.isSelected = controller.isLensAudioMuted
        lensAudioActionView.toggleButton.accessibilityLabel =
            controller.isLensAudioMuted ? "Unmute Lens Audio" : "Mute Lens Audio"
        for (index, action) in lensButtonActionViews.enumerated() {
            let available = controller.isLensButtonAvailable(at: index)
            action.toggleButton.isSelected = available && controller.isLensButtonEnabled(at: index)
            action.toggleButton.alpha = available ? 1 : 0.45
        }
    }

    private static func lensSlotActionView(number: Int, identifier: String) -> CameraConfigurableActionView {
        let view = CameraConfigurableActionView()
        view.configurable = false
        view.toggleButton.accessibilityIdentifier = identifier
        view.toggleButton.accessibilityLabel = "Lens Slot \(number)"
        view.toggleButton.tintColor = .white
        if let image = UIImage(
            systemName: "\(number).circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        ) {
            view.toggleButton.setImage(image, for: .normal)
            view.toggleButton.setImage(image.circleHighlightedImage(radius: 20, color: .white), for: .selected)
        }
        return view
    }

    private static func highDefinitionButtonImage(selected: Bool, tint: UIColor, outline: UIColor?) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { _ in
            if selected {
                tint.setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            }

            let text = "HD" as NSString
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: selected ? UIColor.black : tint,
            ]
            if let outline {
                // Negative width strokes the outline and still fills the letters.
                attributes[.strokeColor] = outline
                attributes[.strokeWidth] = -4
            }
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
        backgroundColor = .clear

        for housing in [buttonStackHousingView, lensButtonStackHousingView] {
            housing.layer.cornerRadius = 8
            housing.layer.cornerCurve = .continuous
            housing.isUserInteractionEnabled = false
            housing.isHidden = true
            housing.translatesAutoresizingMaskIntoConstraints = false
            addSubview(housing)
        }
        addSubview(buttonStackView)
        addSubview(lensButtonStackView)
        // Each housing runs off its screen edge and ends at this view's bottom, where the host's
        // bottom chrome begins, so it reads as that chrome rising behind the buttons.
        housingOverhangConstraints = [
            buttonStackHousingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -32),
            lensButtonStackHousingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 32),
        ]
        let bottomHousingPadding = [
            buttonStackHousingView.topAnchor.constraint(equalTo: buttonStackView.topAnchor, constant: -6),
            lensButtonStackHousingView.topAnchor.constraint(equalTo: lensButtonStackView.topAnchor, constant: -6),
        ]
        let topHousingPadding = [
            buttonStackHousingView.bottomAnchor.constraint(equalTo: buttonStackView.bottomAnchor, constant: 6),
            lensButtonStackHousingView.bottomAnchor.constraint(equalTo: lensButtonStackView.bottomAnchor, constant: 6),
        ]
        let horizontalHousingPadding = [
            buttonStackHousingView.trailingAnchor.constraint(equalTo: buttonStackView.trailingAnchor, constant: 6),
            lensButtonStackHousingView.leadingAnchor.constraint(equalTo: lensButtonStackView.leadingAnchor, constant: -6),
        ]
        housingPaddingConstraints = horizontalHousingPadding + bottomHousingPadding + topHousingPadding
        bottomDockConstraints = bottomHousingPadding + [
            buttonStackHousingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            lensButtonStackHousingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        topDockConstraints = topHousingPadding + [
            buttonStackHousingView.topAnchor.constraint(equalTo: topAnchor),
            lensButtonStackHousingView.topAnchor.constraint(equalTo: topAnchor),
        ]
        NSLayoutConstraint.activate(housingOverhangConstraints + horizontalHousingPadding)
        stackEdgeConstraints = [
            buttonStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            lensButtonStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ]
        stackBottomConstraints = [
            buttonStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            lensButtonStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ]
        stackWidthConstraints = [
            buttonStackView.widthAnchor.constraint(equalToConstant: 40),
            lensButtonStackView.widthAnchor.constraint(equalToConstant: 40),
        ]
        stackTopConstraints = [
            buttonStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            lensButtonStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
        ]
        bottomDockConstraints += stackBottomConstraints + [
            buttonStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            lensButtonStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ]
        topDockConstraints += stackTopConstraints + [
            buttonStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            lensButtonStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(stackEdgeConstraints + stackWidthConstraints + bottomDockConstraints)
        let flipCameraHeightConstraint = flipCameraButton.heightAnchor.constraint(equalToConstant: 40)
        self.flipCameraHeightConstraint = flipCameraHeightConstraint
        NSLayoutConstraint.activate([flipCameraHeightConstraint])
    }
}
