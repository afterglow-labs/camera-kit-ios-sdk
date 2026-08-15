//  Copyright Snap Inc. All rights reserved.

import Combine
import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import SwiftUI

@available(iOS 14.0, *)
/// An observable state object the CameraView can watch for changes to state in CameraKit
public class CameraViewState: NSObject, ObservableObject {
    private var cancelleables: Set<AnyCancellable> = []
    private var hideMessage: DispatchWorkItem?
    private weak var configuredCameraController: CameraController?
    private var synchronizingSelection = false

    weak var cameraController: CameraController! {
        didSet {
            guard let controller = cameraController, oldValue !== controller else { return }
            cancelleables.removeAll()
            controller.uiDelegate = self
            $selectedLens
                .sink { [weak self, weak controller] lens in
                    guard let self, let controller, !self.synchronizingSelection else { return }
                    if let lens {
                        controller.applyLens(lens)
                    } else {
                        controller.clearLens()
                        self.showingMessage = false
                    }
                }.store(in: &cancelleables)
        }
    }

    /// The lenses available for selection
    @Published var lenses: [Lens] = []

    /// The selected lens, if one is selected
    @Published var selectedLens: Lens?

    /// User-facing name of the confirmed active Lens stack.
    @Published var activeLensDisplayName = ""

    /// Stable IDs of the confirmed active Lens stack.
    @Published var activeLensDisplayID = ""

    /// Whether a lens is being loaded or not
    @Published var loading = false

    /// Any hint that a lens has requested be displayed
    @Published var hint: String?

    /// A photo/video the user has captured, if they have captured one
    @Published var captured: Captured?

    /// Whether a diagnostic message is being displayed
    @Published var showingMessage = false

    /// Whether the ring light effect should be displayed.
    @Published var showingRingLight = false

    /// Whether Snap attribution should be displayed.
    @Published var showingSnapAttribution = true

    /// Whether tone mapping is available for the current camera pipeline.
    @Published var toneMapAvailable = false

    /// Whether portrait adjustment is available for the current camera pipeline.
    @Published var portraitAvailable = false

    /// Current ring light intensity selected through the SDK flash control.
    @Published var ringLightIntensity: CGFloat = 0.2

    /// Current ring light color selected through the SDK flash control.
    @Published var ringLightColor: UIColor = .white

    /// Current Camera Kit tone-map amount. Zero means disabled.
    @Published var toneMapAmount: Double = 0

    /// Current Camera Kit portrait blur. Zero means disabled.
    @Published var portraitBlur: Double = 0

    /// Whether non-camera chrome should be hidden for an unobstructed recording/preview.
    @Published var chromeHidden = false

    /// Whether video recording is currently active.
    @Published var recording = false

    /// Whether a completed recording is still being flushed to disk.
    @Published var recordingFinalizing = false

    deinit {
        tearDown()
    }

    func tearDown() {
        hideMessage?.cancel()
        hideMessage = nil
        cancelleables.removeAll()
        recording = false
        recordingFinalizing = false

        if let controller = configuredCameraController {
            controller.cameraKit.adjustments.processor?.removeObserver(self)
            if controller.uiDelegate === self {
                controller.uiDelegate = nil
            }
        }

        configuredCameraController = nil
        cameraController = nil
    }

    func configureIfNeeded(
        cameraController controller: CameraController,
        onChromeHiddenChange: ((Bool) -> Void)?
    ) {
        guard configuredCameraController !== controller else {
            onChromeHiddenChange?(chromeHidden)
            return
        }

        configuredCameraController = controller
        cameraController = controller
        controller.configure(
            orientation: .portrait,
            textInputContextProvider: nil,
            agreementsPresentationContextProvider: nil,
            completion: { [weak self, weak controller] in
                guard let self, let controller, self.configuredCameraController === controller else { return }
                self.updateAdjustmentAvailability()
                controller.cameraKit.adjustments.processor?.addObserver(self)
            }
        )
        updateAdjustmentAvailability()
        onChromeHiddenChange?(chromeHidden)
    }
}

@available(iOS 14.0, *)
extension CameraViewState {
    /// Convenience setter for the captured property
    /// - Parameters:
    ///   - photo: the photo captured
    ///   - error: any error that occurred during capture
    func tookPhoto(_ photo: UIImage?, error: Error?) {
        guard let photo else { return }
        captured = .photo(image: photo)
    }

    /// Convenience setter for the captured property
    /// - Parameters:
    ///   - video: the url to the video captured
    ///   - error: any error that occurred during capture
    func tookVideo(_ video: URL?, error: Error?) {
        guard let video else { return }
        captured = .video(url: video)
    }
}

@available(iOS 14.0, *)
extension CameraViewState: CameraControllerUIDelegate {
    public func cameraControllerRequestedActivityIndicatorShow(_ controller: CameraController) {
        loading = true
    }

    public func cameraControllerRequestedActivityIndicatorHide(_ controller: CameraController) {
        loading = false
    }

    public func cameraController(_ controller: CameraController, updatedLenses lenses: [Lens]) {
        self.lenses = lenses
    }

    public func cameraControllerLensStackDidChange(_ controller: CameraController) {
        synchronizingSelection = true
        selectedLens = controller.currentLens
        activeLensDisplayName = controller.lensDisplayName
        activeLensDisplayID = controller.appliedLenses.map(\.id).joined(separator: " + ")
        synchronizingSelection = false

        hideMessage?.cancel()
        guard controller.currentLens != nil else {
            showingMessage = false
            return
        }
        showingMessage = true
        let hideMessage = DispatchWorkItem { [weak self] in
            self?.showingMessage = false
        }
        self.hideMessage = hideMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: hideMessage)
    }

    public func cameraController(
        _ controller: CameraController, requestedHintDisplay hint: String, for lens: Lens, autohide: Bool
    ) {
        self.hint = hint
        if autohide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if self?.hint == hint {
                    self?.hint = nil
                }
            }
        }
    }

    public func cameraController(_ controller: CameraController, requestedHintHideFor lens: Lens) {
        hint = nil
    }

    public func cameraControllerRequestedRingLightShow(_ controller: CameraController) {
        showingRingLight = true
    }

    public func cameraControllerRequestedRingLightHide(_ controller: CameraController) {
        showingRingLight = false
    }

    public func cameraControllerControlsDidChange(_ controller: CameraController) {
        showingRingLight = controller.isRingLightEnabled
        ringLightIntensity = controller.ringLightIntensity
        ringLightColor = controller.ringLightColor
        toneMapAmount = controller.toneMapAdjustmentAmount
        portraitBlur = controller.portraitAdjustmentBlur
    }

    public func cameraControllerRequestedFlashControlHide(_ controller: CameraController) {
    }

    public func cameraControllerRequestedSnapAttributionViewShow(_ controller: CameraController) {
        showingSnapAttribution = true
    }

    public func cameraControllerRequestedSnapAttributionViewHide(_ controller: CameraController) {
        showingSnapAttribution = false
    }

    public func cameraControllerRequestedCameraFlip(_ controller: CameraController) {
    }
}

@available(iOS 14.0, *)
extension CameraViewState: AdjustmentsProcessorObserver {
    public func processorUpdatedAdjustmentsAvailability(_ adjustmentsProcessor: AdjustmentsProcessor) {
        updateAdjustmentAvailability()
    }

    func updateAdjustmentAvailability() {
        guard let controller = cameraController else { return }
        toneMapAvailable = controller.isToneMapAdjustmentAvailable
        portraitAvailable = controller.isPortraitAdjustmentAvailable
    }
}

enum Captured {
    case photo(image: UIImage)
    case video(url: URL)
}

extension Captured: Identifiable {
    var id: Int {
        switch self {
        case let .photo(image):
            return image.hashValue
        case let .video(url):
            return url.hashValue
        }
    }
}
