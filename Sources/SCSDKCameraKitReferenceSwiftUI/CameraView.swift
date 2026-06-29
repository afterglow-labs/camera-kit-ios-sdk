//  Copyright Snap Inc. All rights reserved.

import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import AVFoundation
import SwiftUI
import UIKit

@available(iOS 14.0, *)
public enum CameraPreviewAspectRatio {
    case fullScreen
    case nineBySixteen
    case threeByFour
    case square

    var widthToHeight: CGFloat? {
        switch self {
        case .fullScreen:
            return nil
        case .nineBySixteen:
            return 9.0 / 16.0
        case .threeByFour:
            return 3.0 / 4.0
        case .square:
            return 1.0
        }
    }
}

@available(iOS 14.0, *)
/// A sample implementation of a minimal SwiftUI view for a CameraKit camera experience.
public struct CameraView: View {
    /// Relevant state for the view
    @StateObject private var state = CameraViewState()

    /// A controller which manages the camera and lenses stack on behalf of the view
    private var cameraController: CameraController

    @Binding private var chromeHidden: Bool
    private let onChromeHiddenChange: ((Bool) -> Void)?
    private let previewAspectRatio: CameraPreviewAspectRatio
    private let showsChromeVisibilityButton: Bool

    public init(
        cameraController: CameraController,
        previewAspectRatio: CameraPreviewAspectRatio = .fullScreen,
        chromeHidden: Binding<Bool> = .constant(false),
        showsChromeVisibilityButton: Bool = true,
        onChromeHiddenChange: ((Bool) -> Void)? = nil
    ) {
        self.cameraController = cameraController
        self.previewAspectRatio = previewAspectRatio
        self._chromeHidden = chromeHidden
        self.showsChromeVisibilityButton = showsChromeVisibilityButton
        self.onChromeHiddenChange = onChromeHiddenChange
    }

    public var body: some View {
        let chromeOpacity = state.chromeHidden ? 0.0 : 1.0

        ZStack {
            PreviewLayer(
                state: state,
                cameraController: cameraController,
                aspectRatio: previewAspectRatio
            )
            .edgesIgnoringSafeArea(.all)
            VStack {
                LensHeader(lensName: cameraController.currentLens?.name ?? "")
                MessageView(
                    lensName: cameraController.currentLens?.name ?? "", lensID: cameraController.currentLens?.id ?? "",
                    showing: state.showingMessage
                )
                Spacer()
                MediaPickerView(provider: cameraController.lensMediaProvider)
                LensFooter(state: state, cameraController: cameraController)
            }
            .opacity(chromeOpacity)
            .allowsHitTesting(!state.chromeHidden)
            SnapAttributionContainerRepresentable()
                .edgesIgnoringSafeArea(.all)
                .opacity(state.showingSnapAttribution && !state.chromeHidden ? 1 : 0)
                .allowsHitTesting(false)
            CameraInclusiveControlsRepresentable(state: state, cameraController: cameraController)
                .edgesIgnoringSafeArea(.all)
                .opacity(chromeOpacity)
                .allowsHitTesting(!state.chromeHidden)
            HintView(hint: state.hint)
                .opacity(chromeOpacity)
            ProgressView()
                .opacity(state.loading && !state.chromeHidden ? 1 : 0)
            if showsChromeVisibilityButton {
                ChromeVisibilityButton(hidden: $state.chromeHidden)
            }
        }.onAppear {
            state.chromeHidden = chromeHidden
            state.configureIfNeeded(
                cameraController: cameraController,
                onChromeHiddenChange: onChromeHiddenChange
            )
        }
        .onChange(of: chromeHidden) { hidden in
            guard state.chromeHidden != hidden else { return }
            state.chromeHidden = hidden
        }
        .onChange(of: state.chromeHidden) { hidden in
            if chromeHidden != hidden {
                chromeHidden = hidden
            }
            onChromeHiddenChange?(hidden)
        }
        .sheet(item: $state.captured, onDismiss: cameraController.reapplyCurrentLens) { item in
            switch item {
            case let .photo(image):
                ImagePreviewView(image: image, snapchatDelegate: cameraController.snapchatDelegate)
                    .edgesIgnoringSafeArea(.bottom)
            case let .video(url):
                VideoPreviewView(video: url, snapchatDelegate: cameraController.snapchatDelegate)
                    .edgesIgnoringSafeArea(.bottom)
            }
        }
    }
}

@available(iOS 14.0, *)
private struct PreviewLayer: View {
    @ObservedObject var state: CameraViewState
    let cameraController: CameraController
    let aspectRatio: CameraPreviewAspectRatio

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PreviewView(cameraKit: cameraController.cameraKit)
                    .onTapGesture(count: 2, perform: cameraController.flipCamera)
                    .gesture(
                        MagnificationGesture(minimumScaleDelta: 0)
                            .onChanged(cameraController.zoomExistingLevel(by:))
                            .onEnded { _ in
                                cameraController.finalizeZoom()
                            })
                RingLightRepresentable(state: state)
                    .allowsHitTesting(false)
                    .opacity(state.showingRingLight && !state.chromeHidden ? 1 : 0)
                RingLightStroke(color: Color(state.ringLightColor))
                    .allowsHitTesting(false)
                    .opacity(state.showingRingLight && !state.chromeHidden ? min(1, max(0.42, state.ringLightIntensity + 0.28)) : 0)
                AspectRatioMatte(availableSize: proxy.size, aspectRatio: aspectRatio.widthToHeight)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black)
    }
}

@available(iOS 14.0, *)
private struct AspectRatioMatte: View {
    let availableSize: CGSize
    let aspectRatio: CGFloat?

    var body: some View {
        ZStack {
            if let frame = matteFrame {
                Color.black
                    .frame(width: availableSize.width, height: topBarHeight(for: frame))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Color.black
                    .frame(width: availableSize.width, height: topBarHeight(for: frame))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                Color.black
                    .frame(width: sideBarWidth(for: frame), height: availableSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Color.black
                    .frame(width: sideBarWidth(for: frame), height: availableSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
    }

    private var matteFrame: CGSize? {
        guard let aspectRatio, aspectRatio > 0, availableSize.width > 0, availableSize.height > 0 else {
            return nil
        }

        let availableRatio = availableSize.width / availableSize.height
        if availableRatio > aspectRatio {
            let height = availableSize.height
            return CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = availableSize.width
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    private func topBarHeight(for frame: CGSize) -> CGFloat {
        max(0, (availableSize.height - frame.height) / 2)
    }

    private func sideBarWidth(for frame: CGSize) -> CGFloat {
        max(0, (availableSize.width - frame.width) / 2)
    }
}

@available(iOS 14.0, *)
private struct RingLightStroke: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(color, lineWidth: ringWidth(for: proxy.size))
                .shadow(color: color.opacity(0.55), radius: 18)
                .padding(2)
        }
    }

    private func ringWidth(for size: CGSize) -> CGFloat {
        max(10, min(22, min(size.width, size.height) * 0.028))
    }
}

@available(iOS 14.0, *)
private struct ChromeVisibilityButton: View {
    @Binding var hidden: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: { hidden.toggle() }) {
                    Image(systemName: hidden ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(hidden ? 0.46 : 0.36))
                        .clipShape(Circle())
                        .opacity(hidden ? 0.86 : 0.9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hidden ? "Show camera controls" : "Hide camera controls")
                .padding(.leading, 14)
                .padding(.bottom, 16)
                Spacer()
            }
        }
    }
}

@available(iOS 14.0, *)
private struct RingLightRepresentable: UIViewRepresentable {
    @ObservedObject var state: CameraViewState

    func makeUIView(context: Context) -> LayoutAwareRingLightContainerView {
        let view = LayoutAwareRingLightContainerView()
        view.apply(intensity: state.ringLightIntensity, color: state.ringLightColor, animated: false)
        return view
    }

    func updateUIView(_ uiView: LayoutAwareRingLightContainerView, context: Context) {
        uiView.apply(intensity: state.ringLightIntensity, color: state.ringLightColor, animated: true)
    }
}

private final class LayoutAwareRingLightContainerView: UIView {
    private let ringLightView = RingLightView()
    private var currentIntensity: CGFloat = 0.2
    private var currentColor: UIColor = .white

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func apply(intensity: CGFloat, color: UIColor, animated: Bool) {
        currentIntensity = intensity
        currentColor = color
        ringLightView.changeColor(to: color)
        setNeedsLayout()
        layoutIfNeeded()
        ringLightView.ringLightGradient.updateIntensity(to: intensity, animated: animated && bounds != .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ringLightView.changeColor(to: currentColor)
        ringLightView.ringLightGradient.updateIntensity(to: currentIntensity, animated: false)
    }

    private func setup() {
        isUserInteractionEnabled = false
        ringLightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringLightView)
        NSLayoutConstraint.activate([
            ringLightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            ringLightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ringLightView.topAnchor.constraint(equalTo: topAnchor),
            ringLightView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private struct SnapAttributionContainerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SnapAttributionContainerView {
        SnapAttributionContainerView()
    }

    func updateUIView(_ uiView: SnapAttributionContainerView, context: Context) {}
}

private final class SnapAttributionContainerView: UIView {
    private let snapAttributionView: SnapAttributionView = {
        let view = SnapAttributionView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        addSubview(snapAttributionView)
        NSLayoutConstraint.activate([
            snapAttributionView.topAnchor.constraint(equalTo: bottomAnchor, constant: -118),
            trailingAnchor.constraint(equalToSystemSpacingAfter: snapAttributionView.trailingAnchor, multiplier: 2.0),
        ])
    }
}

@available(iOS 14.0, *)
private struct CameraInclusiveControlsRepresentable: UIViewRepresentable {
    @ObservedObject var state: CameraViewState
    let cameraController: CameraController

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, cameraController: cameraController)
    }

    func makeUIView(context: Context) -> InclusiveCameraControlsView {
        let view = InclusiveCameraControlsView()
        context.coordinator.controlsView = view
        view.configure(cameraController: cameraController, coordinator: context.coordinator)
        view.updateAdjustmentAvailability(
            tone: state.toneMapAvailable || cameraController.isToneMapAdjustmentAvailable,
            portrait: state.portraitAvailable || cameraController.isPortraitAdjustmentAvailable
        )
        return view
    }

    func updateUIView(_ uiView: InclusiveCameraControlsView, context: Context) {
        uiView.updateAdjustmentAvailability(
            tone: state.toneMapAvailable || cameraController.isToneMapAdjustmentAvailable,
            portrait: state.portraitAvailable || cameraController.isPortraitAdjustmentAvailable
        )
        uiView.updateFlashToggle(for: cameraController.cameraPosition)
    }

    final class Coordinator: NSObject, FlashControlViewDelegate, AdjustmentControlViewDelegate {
        let state: CameraViewState
        let cameraController: CameraController
        weak var controlsView: InclusiveCameraControlsView?

        init(state: CameraViewState, cameraController: CameraController) {
            self.state = state
            self.cameraController = cameraController
        }

        @objc
        func flipCamera() {
            cameraController.flipCamera()
            controlsView?.updateFlashToggle(for: cameraController.cameraPosition)
        }

        func flashControlView(_ view: FlashControlView, selectedRingLightColor color: UIColor) {
            state.ringLightColor = color
        }

        func flashControlView(_ view: FlashControlView, updatedRingLightValue value: Float) {
            state.ringLightIntensity = CGFloat(value)
            state.showingRingLight = value > 0
        }

        func flashControlView(_ view: FlashControlView, updatedFlashMode flashMode: CameraController.FlashMode) {
            cameraController.flashState = .on(flashMode)
            switch flashMode {
            case .ring:
                state.showingRingLight = true
                if state.ringLightIntensity == 0 {
                    state.ringLightIntensity = CGFloat(view.ringLightIntensityValue)
                }
            case .standard:
                state.showingRingLight = false
            }
        }

        func adjustmentControlView(_ control: AdjustmentControlView, sliderValueChanged value: Double) {
            cameraController.adjustmentControlView(control, sliderValueChanged: value)
        }
    }
}

@available(iOS 14.0, *)
private final class InclusiveCameraControlsView: UIView {
    let cameraActionsView = CameraActionsView()
    let flashControlView = FlashControlView()
    let flashControlDismissalHint = UILabel.controlDismissalHint()
    let toneMapControlView: AdjustmentControlView = {
        let view = AdjustmentControlView()
        let variant = AdjustmentControlView.Variant.tone
        view.tag = variant.rawValue
        view.primaryLabel.text = variant.label
        view.accessibilityIdentifier = CameraElements.toneMapControl.id
        view.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_tone_map_control", comment: "")
        return view
    }()
    let toneMapControlDismissalHint = UILabel.controlDismissalHint()
    let portraitControlView: AdjustmentControlView = {
        let view = AdjustmentControlView()
        let variant = AdjustmentControlView.Variant.portrait
        view.tag = variant.rawValue
        view.primaryLabel.text = variant.label
        view.accessibilityIdentifier = CameraElements.portraitControl.id
        view.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_portrait_control", comment: "")
        return view
    }()
    let portraitControlDismissalHint = UILabel.controlDismissalHint()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint, with: event) {
                return hitView
            }
        }
        return nil
    }

    func configure(cameraController: CameraController, coordinator: CameraInclusiveControlsRepresentable.Coordinator) {
        cameraActionsView.flipCameraButton.addTarget(coordinator, action: #selector(coordinator.flipCamera), for: .touchUpInside)

        flashControlView.delegate = coordinator
        toneMapControlView.delegate = coordinator
        portraitControlView.delegate = coordinator

        cameraActionsView.flashActionView.enableAction = { [weak cameraController] in
            cameraController?.enableFlash()
        }
        cameraActionsView.flashActionView.disableAction = { [weak cameraController] in
            cameraController?.disableFlash()
        }

        cameraActionsView.toneMapActionView.enableAction = { [weak self, weak cameraController] in
            guard let amount = cameraController?.enableToneMapAdjustment() else { return }
            self?.toneMapControlView.intensityValue = amount
        }
        cameraActionsView.toneMapActionView.disableAction = { [weak cameraController] in
            cameraController?.disableToneMapAdjustment()
        }

        cameraActionsView.portraitActionView.enableAction = { [weak self, weak cameraController] in
            guard let blur = cameraController?.enablePortraitAdjustment() else { return }
            self?.portraitControlView.intensityValue = blur
        }
        cameraActionsView.portraitActionView.disableAction = { [weak cameraController] in
            cameraController?.disablePortraitAdjustment()
        }

        configureControlVisibilityCallbacks()
        updateFlashToggle(for: cameraController.cameraPosition)
    }

    func updateAdjustmentAvailability(tone: Bool, portrait: Bool) {
        cameraActionsView.toneMapActionView.isHidden = !tone
        cameraActionsView.portraitActionView.isHidden = !portrait
        if !tone {
            toneMapControlView.isHidden = true
            toneMapControlDismissalHint.isHidden = true
        }
        if !portrait {
            portraitControlView.isHidden = true
            portraitControlDismissalHint.isHidden = true
        }
    }

    func updateFlashToggle(for position: AVCaptureDevice.Position) {
        switch position {
        case .front:
            cameraActionsView.setupFlashToggleButtonForFront()
            cameraActionsView.flipCameraButton.accessibilityValue = CameraElements.CameraFlip.front
        case .back:
            cameraActionsView.setupFlashToggleButtonForBack()
            cameraActionsView.flipCameraButton.accessibilityValue = CameraElements.CameraFlip.back
        default:
            break
        }
    }

    private func setup() {
        backgroundColor = .clear
        [cameraActionsView, flashControlView, flashControlDismissalHint, toneMapControlView,
         toneMapControlDismissalHint, portraitControlView, portraitControlDismissalHint].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        flashControlView.accessibilityIdentifier = CameraElements.flashControl.id
        flashControlView.accessibilityLabel = CameraKitLocalizedString(key: "camera_kit_flash_control", comment: "")
        flashControlDismissalHint.accessibilityIdentifier = CameraElements.flashControlDismissalHint.id
        toneMapControlDismissalHint.accessibilityIdentifier = CameraElements.toneMapControlDismissalHint.id
        portraitControlDismissalHint.accessibilityIdentifier = CameraElements.portraitControlDismissalHint.id

        hideAllControls()

        NSLayoutConstraint.activate([
            cameraActionsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            cameraActionsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cameraActionsView.widthAnchor.constraint(equalToConstant: 40),

            flashControlView.trailingAnchor.constraint(equalTo: cameraActionsView.flashActionView.toggleButton.leadingAnchor, constant: -8),
            flashControlView.topAnchor.constraint(equalTo: cameraActionsView.flashActionView.toggleButton.bottomAnchor),
            flashControlDismissalHint.leadingAnchor.constraint(equalTo: flashControlView.leadingAnchor),
            flashControlDismissalHint.trailingAnchor.constraint(equalTo: flashControlView.trailingAnchor),
            flashControlDismissalHint.topAnchor.constraint(equalTo: flashControlView.bottomAnchor),

            toneMapControlView.trailingAnchor.constraint(equalTo: cameraActionsView.toneMapActionView.toggleButton.leadingAnchor, constant: -8),
            toneMapControlView.topAnchor.constraint(equalTo: cameraActionsView.toneMapActionView.toggleButton.bottomAnchor),
            toneMapControlDismissalHint.leadingAnchor.constraint(equalTo: toneMapControlView.leadingAnchor),
            toneMapControlDismissalHint.trailingAnchor.constraint(equalTo: toneMapControlView.trailingAnchor),
            toneMapControlDismissalHint.topAnchor.constraint(equalTo: toneMapControlView.bottomAnchor),

            portraitControlView.trailingAnchor.constraint(equalTo: cameraActionsView.portraitActionView.toggleButton.leadingAnchor, constant: -8),
            portraitControlView.topAnchor.constraint(equalTo: cameraActionsView.portraitActionView.toggleButton.bottomAnchor),
            portraitControlDismissalHint.leadingAnchor.constraint(equalTo: portraitControlView.leadingAnchor),
            portraitControlDismissalHint.trailingAnchor.constraint(equalTo: portraitControlView.trailingAnchor),
            portraitControlDismissalHint.topAnchor.constraint(equalTo: portraitControlView.bottomAnchor),
        ])
    }

    private func configureControlVisibilityCallbacks() {
        cameraActionsView.flashActionView.showActionSettings = { [weak self] in
            self?.show(control: self?.flashControlView, hint: self?.flashControlDismissalHint)
        }
        cameraActionsView.flashActionView.hideActionSettings = { [weak self] in
            self?.hide(control: self?.flashControlView, hint: self?.flashControlDismissalHint)
        }
        cameraActionsView.flashActionView.toggleActionSettingsVisibility = { [weak self] in
            self?.toggle(control: self?.flashControlView, hint: self?.flashControlDismissalHint)
        }

        cameraActionsView.toneMapActionView.showActionSettings = { [weak self] in
            self?.show(control: self?.toneMapControlView, hint: self?.toneMapControlDismissalHint)
        }
        cameraActionsView.toneMapActionView.hideActionSettings = { [weak self] in
            self?.hide(control: self?.toneMapControlView, hint: self?.toneMapControlDismissalHint)
        }
        cameraActionsView.toneMapActionView.toggleActionSettingsVisibility = { [weak self] in
            self?.toggle(control: self?.toneMapControlView, hint: self?.toneMapControlDismissalHint)
        }

        cameraActionsView.portraitActionView.showActionSettings = { [weak self] in
            self?.show(control: self?.portraitControlView, hint: self?.portraitControlDismissalHint)
        }
        cameraActionsView.portraitActionView.hideActionSettings = { [weak self] in
            self?.hide(control: self?.portraitControlView, hint: self?.portraitControlDismissalHint)
        }
        cameraActionsView.portraitActionView.toggleActionSettingsVisibility = { [weak self] in
            self?.toggle(control: self?.portraitControlView, hint: self?.portraitControlDismissalHint)
        }
    }

    private func show(control: UIView?, hint: UIView?) {
        hideAllControls()
        control?.isHidden = false
        hint?.isHidden = false
    }

    private func hide(control: UIView?, hint: UIView?) {
        control?.isHidden = true
        hint?.isHidden = true
    }

    private func toggle(control: UIView?, hint: UIView?) {
        guard let control, let hint else { return }
        let shouldShow = control.isHidden
        hideAllControls()
        control.isHidden = !shouldShow
        hint.isHidden = !shouldShow
    }

    private func hideAllControls() {
        [flashControlView, flashControlDismissalHint, toneMapControlView,
         toneMapControlDismissalHint, portraitControlView, portraitControlDismissalHint].forEach {
            $0.isHidden = true
        }
    }
}

/// A sample implementation of a header view, which shows the lens name.
struct LensHeader: View {
    /// The name of the currently selected lens.
    let lensName: String

    var body: some View {
        Text(lensName)
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.headline)
            .foregroundColor(.white)
            .padding()
    }
}

@available(iOS 14.0, *)
/// A reference implementation of a footer view, which contains a lens carousel, a camera button, and a close button
struct LensFooter: View {
    /// The state of the camera view.
    @ObservedObject var state: CameraViewState

    /// The camera controller.
    let cameraController: CameraController

    var body: some View {
        VStack(spacing: 8) {
            CarouselView(availableLenses: $state.lenses, selectedLens: $state.selectedLens)
                .frame(height: 62)
                .padding(.bottom, 62)
            HStack(spacing: 18) {
                Button(action: takePhoto) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.42))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take photo")

                Button(action: toggleRecording) {
                    Circle()
                        .fill(state.recording ? Color.red.opacity(0.72) : Color.red)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(state.recording ? 0.95 : 0))
                                .frame(width: 12, height: 12)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.recording ? "Stop recording" : "Start recording")
            }
            .frame(height: 42)

            Button(
                action: {
                    state.selectedLens = nil
                },
                label: {
                    Image("ck_close_circle", bundle: BundleHelper.resourcesBundle)
                }
            )
            .frame(width: 32, height: 32)
            .opacity(state.selectedLens == nil ? 0 : 1)
        }
        .padding(.bottom, 38)
    }

    private func takePhoto() {
        cameraController.takePhoto { image, _ in
            guard let image else { return }
            state.captured = .photo(image: image)
            cameraController.clearLens(willReapply: true)
        }
    }

    private func toggleRecording() {
        if state.recording {
            cameraController.finishRecording { url, _ in
                state.recording = false
                guard let url else { return }
                state.captured = .video(url: url)
                cameraController.clearLens(willReapply: true)
            }
        } else {
            state.recording = true
            cameraController.startRecording()
        }
    }
}

/// A reference implementation of a message view, which shows the selected lens name and ID
struct MessageView: View {
    /// The name of the currently selected lens.
    let lensName: String

    /// The ID of the currently selected lens.
    let lensID: String

    /// Whether or not the message view is being displayed.
    let showing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(lensName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(lensID)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color(white: 0, opacity: 0.65))
            .cornerRadius(4)
            .opacity(showing ? 1 : 0)
            .animation(.easeInOut, value: showing)
            .padding()
            Spacer()
        }
    }
}

/// A reference implementation of a hint view, which shows hints requested to be displayed by a lens
struct HintView: View {
    /// The hint to be displayed.
    let hint: String?

    var body: some View {
        Text(hint ?? "")
            .font(.system(size: 20))
            .bold()
            .foregroundColor(.white)
            .opacity(hint == nil ? 0 : 1)
    }
}
