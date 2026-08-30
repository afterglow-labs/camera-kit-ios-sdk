//  Copyright Snap Inc. All rights reserved.

import UIKit

public protocol NoseAdjustmentsControlViewDelegate: AnyObject {
    /// Notifies the delegate as the native Nose Adjustments controls change.
    /// `done` is true when Camera Kit should reapply the Lens with the final values.
    func noseAdjustmentsControlView(
        _ control: NoseAdjustmentsControlView,
        updated values: NoseAdjustmentValues,
        done: Bool
    )
}

/// Native controls for the Style, Width, Height, and Nose Gap inputs authored by the Nose Adjustments Lens.
public final class NoseAdjustmentsControlView: UIView {
    public weak var delegate: NoseAdjustmentsControlViewDelegate?

    public var values: NoseAdjustmentValues {
        get {
            NoseAdjustmentValues(
                width: Double(widthSlider.value),
                height: Double(heightSlider.value),
                gap: Double(gapSlider.value)
            )
        }
        set {
            setValues(newValue, preset: NoseAdjustmentPreset.matching(newValue))
        }
    }

    public private(set) var selectedPreset: NoseAdjustmentPreset? = .original

    public let styleSlider = ControlSlider()
    public let widthSlider = ControlSlider()
    public let heightSlider = ControlSlider()
    public let gapSlider = ControlSlider()

    public let styleValueLabel = UILabel()
    public let widthValueLabel = UILabel()
    public let heightValueLabel = UILabel()
    public let gapValueLabel = UILabel()

    private let blurEffectView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStack = UIStackView()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 20
        layer.masksToBounds = true
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: 220, height: UIView.noIntrinsicMetric)
    }

    private func commonInit() {
        setupBackground()
        setupContent()
        configureSliders()
        setValues(.original, preset: .original)
    }

    private func setupBackground() {
        addSubview(blurEffectView)
        NSLayoutConstraint.activate([
            blurEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurEffectView.topAnchor.constraint(equalTo: topAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupContent() {
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        let titleLabel = UILabel()
        titleLabel.text = "Nose Adjustments"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.sc_demiBoldFont(size: 17)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        contentStack.addArrangedSubview(titleLabel)

        addSliderRow(title: "Style", valueLabel: styleValueLabel, slider: styleSlider)
        addSliderRow(title: "Width", valueLabel: widthValueLabel, slider: widthSlider)
        addSliderRow(title: "Height", valueLabel: heightValueLabel, slider: heightSlider)
        addSliderRow(title: "Nose Gap", valueLabel: gapValueLabel, slider: gapSlider)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    private func addSliderRow(title: String, valueLabel: UILabel, slider: ControlSlider) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.sc_demiBoldFont(size: 13)

        valueLabel.textColor = UIColor(hex: 0xFFFC00)
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let labels = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        labels.axis = .horizontal
        labels.alignment = .center

        let row = UIStackView(arrangedSubviews: [labels, slider])
        row.axis = .vertical
        row.spacing = 2
        contentStack.addArrangedSubview(row)

        slider.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func configureSliders() {
        styleSlider.minimumValue = Float(NoseAdjustmentPreset.allCases.first?.rawValue ?? 0)
        styleSlider.maximumValue = Float(NoseAdjustmentPreset.allCases.last?.rawValue ?? 0)
        styleSlider.accessibilityLabel = "Nose style"
        styleSlider.accessibilityIdentifier = CameraElements.noseStyleSlider.id

        configureFineSlider(widthSlider, label: "Nose width", identifier: CameraElements.noseWidthSlider.id)
        configureFineSlider(heightSlider, label: "Nose height", identifier: CameraElements.noseHeightSlider.id)
        configureFineSlider(gapSlider, label: "Nose gap", identifier: CameraElements.noseGapSlider.id)

        for slider in [styleSlider, widthSlider, heightSlider, gapSlider] {
            slider.delegate = self
        }
    }

    private func configureFineSlider(_ slider: ControlSlider, label: String, identifier: String) {
        slider.minimumValue = -1
        slider.maximumValue = 1
        slider.accessibilityLabel = label
        slider.accessibilityIdentifier = identifier
    }

    private func setValues(_ values: NoseAdjustmentValues, preset: NoseAdjustmentPreset?) {
        selectedPreset = preset
        widthSlider.setValue(Float(values.width), animated: false)
        heightSlider.setValue(Float(values.height), animated: false)
        gapSlider.setValue(Float(values.gap), animated: false)
        if let preset {
            styleSlider.setValue(Float(preset.rawValue), animated: false)
        }
        updateValueLabels()
    }

    private func updateValueLabels() {
        styleValueLabel.text = selectedPreset?.displayName ?? "Custom"
        widthValueLabel.text = Self.formatted(widthSlider.value)
        heightValueLabel.text = Self.formatted(heightSlider.value)
        gapValueLabel.text = Self.formatted(gapSlider.value)
        styleSlider.accessibilityValue = styleValueLabel.text
        widthSlider.accessibilityValue = widthValueLabel.text
        heightSlider.accessibilityValue = heightValueLabel.text
        gapSlider.accessibilityValue = gapValueLabel.text
    }

    private static func formatted(_ value: Float) -> String {
        String(format: "%+.2f", value)
    }
}

extension NoseAdjustmentsControlView: ControlSliderDelegate {
    public func controlSlider(_ slider: ControlSlider, updatedValue value: Float, done: Bool) {
        if slider === styleSlider {
            let index = Int(value.rounded())
            guard let preset = NoseAdjustmentPreset(rawValue: index) else { return }
            styleSlider.setValue(Float(index), animated: false)
            setValues(preset.values, preset: preset)
        } else {
            selectedPreset = NoseAdjustmentPreset.matching(values)
            updateValueLabels()
        }
        delegate?.noseAdjustmentsControlView(self, updated: values, done: done)
    }
}
