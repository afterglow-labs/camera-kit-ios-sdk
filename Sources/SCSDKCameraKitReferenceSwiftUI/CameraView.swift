//  Copyright Snap Inc. All rights reserved.

import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import SwiftUI
import UIKit

@available(iOS 14.0, *)
/// A sample implementation of a minimal SwiftUI view for a CameraKit camera experience.
public struct CameraView: View {
    /// Relevant state for the view
    @StateObject private var state = CameraViewState()

    /// A controller which manages the camera and lenses stack on behalf of the view
    private var cameraController: CameraController

    public init(cameraController: CameraController) {
        self.cameraController = cameraController
        cameraController.configure(
            orientation: .portrait, textInputContextProvider: nil, agreementsPresentationContextProvider: nil,
            completion: nil
        )
    }

    public var body: some View {
        ZStack {
            PreviewView(cameraKit: cameraController.cameraKit)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture(count: 2, perform: cameraController.flipCamera)
                .gesture(
                    MagnificationGesture(minimumScaleDelta: 0)
                        .onChanged(cameraController.zoomExistingLevel(by:))
                        .onEnded { _ in
                            cameraController.finalizeZoom()
                        })
            RingLightRepresentable()
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)
                .opacity(state.showingRingLight ? 1 : 0)
            VStack {
                LensHeader(
                    lensName: cameraController.currentLens?.name ?? "", flipCameraAction: cameraController.flipCamera
                )
                MessageView(
                    lensName: cameraController.currentLens?.name ?? "", lensID: cameraController.currentLens?.id ?? "",
                    showing: state.showingMessage
                )
                Spacer()
                MediaPickerView(provider: cameraController.lensMediaProvider)
                LensFooter(state: state, cameraController: cameraController)
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SnapAttributionRepresentable()
                        .frame(width: 84, height: 28)
                        .padding(.trailing, 16)
                        .padding(.bottom, 112)
                }
            }
            .opacity(state.showingSnapAttribution ? 1 : 0)
            .allowsHitTesting(false)
            HintView(hint: state.hint)
            ProgressView()
                .opacity(state.loading ? 1 : 0)
        }.onAppear {
            state.cameraController = cameraController
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

private struct RingLightRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> LayoutAwareRingLightContainerView {
        let view = LayoutAwareRingLightContainerView()
        view.apply(intensity: 0.2, color: .white, animated: false)
        return view
    }

    func updateUIView(_ uiView: LayoutAwareRingLightContainerView, context: Context) {
        uiView.apply(intensity: 0.2, color: .white, animated: true)
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

private struct SnapAttributionRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SnapAttributionView {
        SnapAttributionView()
    }

    func updateUIView(_ uiView: SnapAttributionView, context: Context) {}
}

/// A sample implementation of a header view, which shows the lens name and a camera flip button
struct LensHeader: View {
    /// The name of the currently selected lens.
    let lensName: String

    /// An action to call when the camera flip button is tapped.
    let flipCameraAction: () -> Void

    var body: some View {
        ZStack {
            Text(lensName)
                .frame(alignment: .center)
                .font(.headline)
                .foregroundColor(.white)
            HStack {
                Spacer()
                Button(action: flipCameraAction) {
                    Image("ck_camera_flip", bundle: BundleHelper.resourcesBundle)
                }
            }
        }.padding()
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
        ZStack {
            CarouselView(availableLenses: $state.lenses, selectedLens: $state.selectedLens)
            CameraButton(
                recordingStart: cameraController.startRecording, recordingCancel: cameraController.cancelRecording,
                recordingFinish: {
                    cameraController.finishRecording { url, _ in
                        guard let url else { return }
                        state.captured = .video(url: url)
                        cameraController.clearLens(willReapply: true)
                    }
                },
                photoCapture: {
                    cameraController.takePhoto { image, _ in
                        guard let image else { return }
                        state.captured = .photo(image: image)
                        cameraController.clearLens(willReapply: true)
                    }
                }
            )
        }
        Button(
            action: {
                state.selectedLens = nil
            },
            label: {
                Image("ck_close_circle", bundle: BundleHelper.resourcesBundle)
            }
        )
        .padding(.top)
        .opacity(state.selectedLens == nil ? 0 : 1)
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
