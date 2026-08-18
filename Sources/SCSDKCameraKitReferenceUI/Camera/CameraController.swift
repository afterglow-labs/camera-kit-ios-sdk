//  Copyright Snap Inc. All rights reserved.

import ARKit
import AVFoundation
import AVKit
import SCSDKCameraKit
import SCSDKCameraKitCompositeLensRuntime
import UIKit

public protocol CameraControllerUIDelegate: AnyObject {
    /// Notifies the delegate that the camera controller has resolved a new list of available lenses
    /// - Parameters:
    ///   - controller: The camera controller.
    ///   - lenses: The newly available lenses.
    func cameraController(_ controller: CameraController, updatedLenses lenses: [Lens])

    /// Notifies the delegate that the camera controller is currently in a loading state, and an activity indicator should be displayed.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedActivityIndicatorShow(_ controller: CameraController)

    /// Notifies the delegate that the camera controller is no longer in a loading state, and an activity indicator should be hidden.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedActivityIndicatorHide(_ controller: CameraController)

    /// Notifies the delegate that the flash state is on in ring light mode and that the ring light effect should be shown.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedRingLightShow(_ controller: CameraController)

    /// Notifies the delegate that the flash state is no longer in ring light mode and that the ring light effect should be hidden.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedRingLightHide(_ controller: CameraController)

    /// Notifies the delegate that Camera Kit adjustment or ring-light state changed.
    /// Implementations should refresh any controls that mirror the controller's public state.
    func cameraControllerControlsDidChange(_ controller: CameraController)

    /// Notifies the delegate after Camera Kit reaches a new confirmed Lens layer state.
    func cameraControllerLensStackDidChange(_ controller: CameraController)

    /// Notifies the delegate that the flash state has changed such that the flash control should be hidden.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedFlashControlHide(_ controller: CameraController)

    /// Notifies the delegate that the snap attribution should be shown. For example, after the agreements have been accepted.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedSnapAttributionViewShow(_ controller: CameraController)

    /// Notifies the delegate that the snap attribution should be hidden. For example, when a video is being recorded.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedSnapAttributionViewHide(_ controller: CameraController)

    /// Notifies the delegate that the camera position should be flipped.
    /// - Parameter controller: The camera controller.
    func cameraControllerRequestedCameraFlip(_ controller: CameraController)

    /// Notifies the delegate that a lens has requested that a hint should be displayed
    /// - Parameters:
    ///   - controller: The camera controller.
    ///   - hint: The hint text that should be displayed.
    ///   - lens: The requesting lens.
    ///   - autohide: Whether or not the hint should be automatically hidden, after a callee-determined amount of time.
    func cameraController(
        _ controller: CameraController, requestedHintDisplay hint: String, for lens: Lens, autohide: Bool
    )

    /// Notifies the delegate that any hints requested by the specified lens should be hidden
    /// - Parameters:
    ///   - controller: The camera controller.
    ///   - lens: The lens whose hints should be hidden.
    func cameraController(_ controller: CameraController, requestedHintHideFor lens: Lens)
}

public extension CameraControllerUIDelegate {
    func cameraControllerControlsDidChange(_ controller: CameraController) {}
    func cameraControllerLensStackDidChange(_ controller: CameraController) {}
}

/// Selects the rear capture device used as Camera Kit's input.
public enum BackCameraDeviceMode: String, CaseIterable, Sendable {
    /// Uses Apple's virtual multi-camera device when available.
    case automatic
    /// Keeps the physical ultra-wide camera active so zoom remains digital on that lens.
    case ultraWide
}

// MARK: Class Definition and State

/// A controller which manages the camera and lenses stack on behalf of its owner
open class CameraController: NSObject, LensRepositoryGroupObserver, LensPrefetcherObserver, LensHintDelegate,
    MediaPickerViewDelegate, AdjustmentControlViewDelegate
{
    // MARK: - Public API

    // MARK: Public vars

    /// A capture session we'll use for camera input.
    public let captureSession: AVCaptureSession

    private let captureSessionQueue = DispatchQueue(label: "com.snap.camerakit.reference-ui.capture-session")
    private let prefetchResourceQueue = DispatchQueue(label: "com.snap.camerakit.reference-ui.prefetch-resources")
    private var configuredOrientation: AVCaptureVideoOrientation = .portrait
    private var configuredTextInputContextProvider: TextInputContextProvider?
    private var configuredAgreementsPresentationContextProvider: AgreementsPresentationContextProvider?
    private var activePrefetchGroupIDs: Set<String> = []
    private var prefetchTasksByGroupID: [String: LensPrefetcherTask] = [:]
    private var prefetchedLensesByGroupID: [String: [Lens]] = [:]

    /// The CameraKit session
    public let cameraKit: CameraKitProtocol

    /// The position of the camera.
    public private(set) var cameraPosition: AVCaptureDevice.Position = .front {
        didSet {
            cameraKit.cameraPosition = cameraPosition
            captureSessionQueue.async { [weak self] in
                self?.replaceVideoInputIfNeeded(for: self?.cameraPosition ?? .front)
            }
        }
    }

    // MARK: Outputs

    /// An output used for taking still photos.
    public private(set) var photoCaptureOutput: PhotoCaptureOutput?
    private var nativePhotoCaptureOutput: AVCapturePhotoOutput?

    /// An output used for recording videos.
    public var recorder: Recorder?

    /// Encoder settings used for the next post-Lens recording.
    public private(set) var recordingConfiguration: RecordingConfiguration?
    private let recordingResolutionOutput = RecordingResolutionOutput()
    private var recordingResolutionOutputAttached = false

    /// Whether the caller has requested Camera Kit's native high-definition Lens rendering path.
    public private(set) var isHighDefinitionLensRenderingEnabled = false

    /// Whether the native runtime currently has a high-definition rendering override applied.
    public private(set) var isHighDefinitionLensRenderingActive = false

    /// The confirmed Lens rendering dimensions applied by HD mode.
    public private(set) var highDefinitionLensRenderingSize: CGSize?

    /// Whether the complete high-definition camera mode is requested.
    public var isHighDefinitionModeEnabled: Bool {
        isHighDefinitionLensRenderingEnabled
    }

    /// An output used for live web preview streaming.
    public private(set) var streamOutput: CameraKitWebSocketStreamOutput?

    // MARK: Data providers

    /// Media provider for CameraKit.
    public let lensMediaProvider = LensMediaPickerProviderPhotoLibrary(defaultAssetTypes: [.image, .imageCroppedToFace])

    // MARK: Delegates

    /// Snapchat delegate for requests to open the main Snapchat app.
    public weak var snapchatDelegate: SnapchatDelegate?

    /// Delegate for responding to UI requests from camera controller.
    public weak var uiDelegate: CameraControllerUIDelegate?

    // MARK: State

    /// The confirmed pinned base Lens, if one is active.
    public var pinnedBaseLens: Lens? {
        readLensState { activeLensStack.pinnedBase }
    }

    /// The confirmed persistent Retouch Lens, if one is active.
    public var activeRetouchLens: Lens? {
        readLensState {
            activePersistentLens(matching: configuredRetouchLens)
        }
    }

    /// Whether a dedicated Retouch Lens has been supplied by the host app.
    public var isRetouchAvailable: Bool {
        readLensState { configuredRetouchLens != nil }
    }

    /// Whether the dedicated Retouch layer is requested for this camera session.
    public var isRetouchEnabled: Bool {
        readLensState { retouchRequestedEnabled }
    }

    /// Retouch implementations currently supplied by the host app.
    public var availableRetouchLensVariants: [RetouchLensVariant] {
        readLensState { configuredRetouchOptions.availableVariants }
    }

    /// The Retouch implementation used the next time the layer is enabled, or currently in use.
    public var selectedRetouchLensVariant: RetouchLensVariant {
        readLensState {
            configuredRetouchOptions.resolvedVariant(preferred: selectedRetouchVariant) ?? selectedRetouchVariant
        }
    }

    /// The confirmed persistent Rhinoplasty Lens, if one is active.
    public var activeRhinoplastyLens: Lens? {
        readLensState {
            activePersistentLens(matching: configuredRhinoplastyLens)
        }
    }

    /// Whether a dedicated Rhinoplasty Lens has been supplied by the host app.
    public var isRhinoplastyAvailable: Bool {
        readLensState { configuredRhinoplastyLens != nil }
    }

    /// Whether the dedicated Rhinoplasty layer is requested for this camera session.
    public var isRhinoplastyEnabled: Bool {
        readLensState { rhinoplastyRequestedEnabled }
    }

    /// Confirmed active Lenses in Camera Kit application order: permanent controls, pinned base, then top.
    public var appliedLenses: [Lens] {
        readLensState { activeLensStack.applied }
    }

    /// The currently selected Lens. A top Lens takes precedence over a pinned base.
    public var currentLens: Lens? {
        readLensState { activeLensStack.current }
    }

    /// User-facing description of the confirmed active Lens stack.
    public var lensDisplayName: String {
        readLensState {
            LensLayerDisplay.name(
                persistentBases: activeLensStack.persistentBases.map(lensName),
                base: activeLensStack.pinnedBase.map(lensName),
                top: activeLensStack.selectedTop.map(lensName)
            )
        }
    }

    /// Lenses exposed to the reference carousel. Dedicated permanent-control Lenses are excluded.
    public var carouselLenses: [Lens] {
        let hiddenControlIdentities = readLensState {
            (configuredRetouchOptions.values + [configuredRhinoplastyLens].compactMap { $0 })
                .map { identity(for: $0) }
        }
        return groupIDs
            .flatMap { cameraKit.lenses.repository.lenses(groupID: $0) }
            .filter { lens in
                let lensIdentity = identity(for: lens)
                return !hiddenControlIdentities.contains(lensIdentity)
            }
    }

    /// Whether the current Camera Kit processor exposes its native composite-Lens entry point.
    public var supportsCompositeLenses: Bool {
        SCCameraKitProcessorSupportsCompositeLenses(cameraKit.lenses.processor)
    }

    /// Whether this Camera Kit runtime exposes its native high-definition YUV rendering path.
    public var supportsHighDefinitionLensRendering: Bool {
        SCCameraKitProcessorSupportsHighDefinitionRendering(cameraKit.lenses.processor)
    }

    /// List of lens repository groups to observe/show in carousel
    public var groupIDs: [String] = [] {
        didSet {
            let removedIDs = Set(oldValue).subtracting(groupIDs)
            let addedIDs = Set(groupIDs).subtracting(oldValue)
            let activeIDs = Set(groupIDs)
            prefetchResourceQueue.async { [weak self] in
                guard let self else { return }
                self.activePrefetchGroupIDs = activeIDs
                for groupID in removedIDs {
                    self.releasePrefetchResources(forGroupID: groupID)
                }
            }
            for group in removedIDs {
                cameraKit.lenses.repository.removeObserver(self, groupID: group)
            }
            for group in addedIDs {
                cameraKit.lenses.repository.addObserver(self, groupID: group)
            }
            // you can also observe a single lens in a group if you only care about a specific lens
            // cameraKit.lenses.repository.cameraKit.lenses.repository.addObserver(self, specificLensID: "123", groupID: "1")
            // and then get the lens after by calling
            // cameraKit.lenses.repository.lens(id: "123", groupID: "1");
        }
    }

    /// Whether or not the tone map adjustment is available for the current device.
    /// This variable should be checked before showing any UI associated with the tone map adjustment.
    public var isToneMapAdjustmentAvailable: Bool {
        cameraKit.adjustments.processor?.isAdjustmentAvailable(ToneMapAdjustment()) ?? false
    }

    /// Whether or not the portrait adjustment is available for the current device.
    /// This variable should be checked before showing any UI associated with the portrait adjustment.
    public var isPortraitAdjustmentAvailable: Bool {
        cameraKit.adjustments.processor?.isAdjustmentAvailable(PortraitAdjustment()) ?? false
    }

    /// Current preferred exposure bias for the active capture device.
    public private(set) var preferredExposureTargetBias: Float = 0

    /// Current preferred warmth adjustment for the active capture device.
    public private(set) var preferredWhiteBalanceWarmth: Float = 0

    /// Current preferred tint adjustment for the active capture device.
    public private(set) var preferredWhiteBalanceTint: Float = 0

    /// The current state of the camera flash.
    public var flashState: FlashState = .off {
        didSet {
            handleFlashStateChange(oldValue: oldValue)
        }
    }

    /// Called on the main queue whenever public Camera Kit control state changes.
    public var controlsDidChange: (() -> Void)?

    /// The current intensity of the front-facing screen ring light.
    public private(set) var ringLightIntensity: CGFloat = 0.2

    /// The current color of the front-facing screen ring light.
    public private(set) var ringLightColor: UIColor = .white

    /// Whether the front-facing screen ring light is currently enabled.
    public var isRingLightEnabled: Bool {
        flashState == .on(.ring)
    }

    /// The requested Camera Kit tone-map amount. Zero means disabled.
    public private(set) var toneMapAdjustmentAmount: Double = 0

    /// The requested Camera Kit portrait blur. Zero means disabled.
    public private(set) var portraitAdjustmentBlur: Double = 0

    /// Width-to-height ratio used for captured photos and videos. Nil follows the screen ratio.
    public private(set) var captureAspectRatio: CGFloat?

    /// Rear capture device selection. Automatic preserves Apple's normal lens switching behavior.
    public private(set) var backCameraDeviceMode: BackCameraDeviceMode = .automatic

    // MARK: Initializers

    /// Returns a camera controller that is initialized with a newly created AVCaptureSession stack
    /// and CameraKit session with the specified configuration and list of group IDs.
    /// - Parameter sessionConfig: Config to configure session with application id and api token.
    /// Pass this in if you wish to dynamically update or overwrite the application id and api token in the application's `Info.plist`.
    public convenience init(sessionConfig: SessionConfig? = nil) {
        // this is how you configure properties for a CameraKit Session
        // max size of lens content cache = 150 * 1024 * 1024 = 150MB
        // 150MB to make sure that some lenses that use large assets such as the ones required for
        // 3D body tracking (https://lensstudio.snapchat.com/templates/object/3d-body-tracking) have
        // enough cache space to fit alongside other lenses.
        let lensesConfig = LensesConfig(cacheConfig: CacheConfig(lensContentMaxSize: 150 * 1024 * 1024))
        let cameraKit = Session(sessionConfig: sessionConfig, lensesConfig: lensesConfig, errorHandler: nil)
        let captureSession = AVCaptureSession()
        self.init(cameraKit: cameraKit, captureSession: captureSession)
    }

    /// Init with camera kit session, capture session, and lens holder
    /// - Parameters:
    ///   - cameraKit: camera kit session
    ///   - captureSession: avcapturesession
    public init(cameraKit: CameraKitProtocol, captureSession: AVCaptureSession) {
        self.cameraKit = cameraKit
        self.captureSession = captureSession
        super.init()
        lensQueue.setSpecific(key: lensQueueKey, value: ())
    }

    // MARK: Configuration

    /// Configures the overall camera and lenses stack.
    /// - Parameters:
    ///   - orientation: the orientation
    ///   - completion:  a nullable completion that is called after configuration is done.
    ///                  In case it's a first app start (when camera permission is not determined yet) a completion will be called after the prompt.
    public func configure(
        orientation: AVCaptureVideoOrientation,
        textInputContextProvider: TextInputContextProvider?,
        agreementsPresentationContextProvider: AgreementsPresentationContextProvider?,
        completion: (() -> Void)?
    ) {
        configuredOrientation = orientation
        configuredTextInputContextProvider = textInputContextProvider
        configuredAgreementsPresentationContextProvider = agreementsPresentationContextProvider
        configureNotifications()
        promptForAccessIfNeeded { [self] in
            captureSessionQueue.async { [self] in
                configureCaptureSession()
                configurePhotoCapture()
                configureLensesOnCaptureSessionQueue(
                    orientation: orientation,
                    textInputContextProvider: textInputContextProvider,
                    agreementsPresentationContextProvider: agreementsPresentationContextProvider
                )
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }

    /// Stops CameraKit and the underlying capture session.
    ///
    /// Call this before replacing one reference camera implementation with another so that only one
    /// CameraKit/capture pipeline owns the camera at a time.
    public func stop(completion: (() -> Void)? = nil) {
        NotificationCenter.default.removeObserver(self)
        isAdjustingExposureObservation = nil
        isAdjustingFocusObservation = nil
        groupIDs = []
        stopPendingLensOperations()

        captureSessionQueue.async { [self] in
            stopWebSocketStreaming()
            prefetchResourceQueue.sync {
                releaseAllPrefetchResources()
            }
            if let recorder {
                recorder.finishRecording(completion: nil)
                cameraKit.remove(output: recorder.output)
                self.recorder = nil
            }
            deactivateRecordingResolutionOutput()
            clearHighDefinitionLensRenderingOverride()
            if let photoCaptureOutput {
                cameraKit.remove(output: photoCaptureOutput)
                self.photoCaptureOutput = nil
            }
            self.nativePhotoCaptureOutput = nil
            cameraKit.activeInput.stopRunning()
            cameraKit.stop {
                self.lensQueue.async {
                    self.desiredLensStack.reset()
                    self.activeLensStack.reset()
                    self.configuredRetouchLens = nil
                    self.configuredRetouchOptions = RetouchLensOptions(standard: nil, machineLearning: nil)
                    self.selectedRetouchVariant = .standard
                    self.retouchRequestedEnabled = false
                    self.configuredRhinoplastyLens = nil
                    self.rhinoplastyRequestedEnabled = false
                    DispatchQueue.main.async {
                        self.uiDelegate?.cameraControllerLensStackDidChange(self)
                        self.uiDelegate = nil
                        completion?()
                    }
                }
            }
        }
    }

    /// Configures the lenses pipeline.
    /// - Parameter orientation: the camera orientation.
    open func configureLenses(
        orientation: AVCaptureVideoOrientation,
        textInputContextProvider: TextInputContextProvider?,
        agreementsPresentationContextProvider: AgreementsPresentationContextProvider?
    ) {
        captureSessionQueue.async { [self] in
            configureLensesOnCaptureSessionQueue(
                orientation: orientation,
                textInputContextProvider: textInputContextProvider,
                agreementsPresentationContextProvider: agreementsPresentationContextProvider
            )
        }
    }

    private func configureLensesOnCaptureSessionQueue(
        orientation: AVCaptureVideoOrientation,
        textInputContextProvider: TextInputContextProvider?,
        agreementsPresentationContextProvider: AgreementsPresentationContextProvider?
    ) {
        // If your lenses need TrueDepth-based face tracking (for ARKit face lenses or true size lenses),
        // use this initializer instead. Please note your app will be subject to additional app review,
        // concerning your usage of the TrueDepth camera.
        /*
         let config = ARFaceTrackingConfiguration()
         config.maximumNumberOfTrackedFaces = 0

         let arInput = ARSessionInput(session: ARSession(), frontCameraConfiguration: config)
          */

        do {
            try CameraKitAudioSession.activateForCameraRecording()
        } catch {
            print("[CameraKit Audio] Could not activate the video-recording audio session: \(error.localizedDescription)")
        }

        let dataProvider = configureDataProvider()
        // Create CameraKit inputs off the main thread. AVSessionInput may touch AVCaptureSession internals
        // during initialization, and AVCaptureSession startRunning must not happen on the main thread.
        let input = AVSessionInput(session: captureSession)
        let arInput = ARSessionInput()

        // Start the actual CameraKit session. Once the session is started, CameraKit will begin processing frames and
        // sending output. The lens processor (cameraKit.lenses.processor) will be instantiated at this point, and
        // you can start sending commands to it (such as applying/clearing lenses).
        cameraKit.start(
            input: input,
            arInput: arInput,
            cameraPosition: .front,
            videoOrientation: orientation,
            dataProvider: dataProvider,
            hintDelegate: self,
            textInputContextProvider: textInputContextProvider,
            agreementsPresentationContextProvider: agreementsPresentationContextProvider
        )

        // Start the capture session. It's important you start the capture session after starting the CameraKit session
        // because the CameraKit input and session configures the capture session implicitly and you may run into a
        // race condition which causes some audio and video output frames to be lost, resulting in a blank preview view
        input.startRunning()
        lensQueue.async { [weak self] in
            guard let self, !self.desiredLensStack.applied.isEmpty else { return }
            self.applyDesiredLensStackIfProcessorAvailable(completion: nil)
        }
        applyPreferredExposureTargetBias()
        applyPreferredWhiteBalanceAdjustment()
        DispatchQueue.main.async { [weak self] in
            self?.refreshHighDefinitionLensRendering()
            self?.applyPreferredToneMapAdjustment()
            self?.applyPreferredPortraitAdjustment()
        }
    }

    /// Configures the data provider for lenses. Subclasses may override this to customize their data provider.
    /// - Returns: a configured data provider.
    open func configureDataProvider() -> DataProviderComponent {
        // By default, CameraKit will handle data providers (such as device motion),
        // but if you want to handle specific data provider(s), pass them in here, example:
        DataProviderComponent(
            deviceMotion: nil, userData: UserDataProvider(), lensHint: nil, location: nil,
            mediaPicker: lensMediaProvider
        )
    }

    // MARK: Camera Control

    /// Zoom in by a given factor from whatever the current zoom level is
    /// - Parameter factor: the factor to zoom by.
    /// - Note: the zoom level will be capped to a minimum level of 1.0.
    public func zoomExistingLevel(by factor: CGFloat) {
        zoomLevel = max(1, lastZoomLevel * factor)
    }

    /// Save whatever the current zoom level is.
    public func finalizeZoom() {
        lastZoomLevel = zoomLevel
    }

    /// Flips the camera to the other side
    public func flipCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
        updateFlashAfterFlip()
        notifyControlsDidChange()
    }

    /// Options to support when setting a point of interest
    public struct PointOfInterestOptions: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        // Option to enable rebalancing exposure when setting the camera's point of interest
        public static let exposure = PointOfInterestOptions(rawValue: 1 << 0)

        // Option to enable refocusing the camera when setting the camera's point of interest
        public static let focus = PointOfInterestOptions(rawValue: 1 << 1)
    }

    /// Sets camera point of interest for operations in the option set. Also adds observers for the current device such
    /// that once the focusing/exposure rebalancing operations are complete, continuous autofocus/autoexposure
    /// are restored (see observeValue)
    /// - Parameters:
    ///  - point: The point at which to set the point of interest. Note that the point provided should conform to the capture device's coordinate system.
    ///  - options: The operations to enable setting the point of interest for. Focusing and rebalancing exposure at the specified point enabled by default.
    public func setPointOfInterest(at point: CGPoint, for options: PointOfInterestOptions = [.exposure, .focus]) {
        guard
            !(cameraKit.activeInput is ARInput),
            let device = cameraInputDevice
        else {
            return
        }

        do {
            try device.lockForConfiguration()

            if
                options.contains(.exposure), device.isExposurePointOfInterestSupported,
                device.isExposureModeSupported(.autoExpose)
            {
                isAdjustingFocusObservation = device.observe(
                    \.isAdjustingExposure,
                    options: .new,
                    changeHandler: restoreContinuousAutoExposure
                )

                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            if
                options.contains(.focus), device.isFocusPointOfInterestSupported,
                device.isFocusModeSupported(.autoFocus)
            {
                isAdjustingExposureObservation = device.observe(
                    \.isAdjustingFocus,
                    options: .new,
                    changeHandler: restoreContinuousAutoFocus
                )

                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }

            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to set point of interest")
            return
        }
    }

    // MARK: Taking Photos

    /// Takes a photo.
    /// - Parameter completion: completion to be called with the photo or an error.
    open func takePhoto(completion: ((UIImage?, Error?) -> Void)?) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashState.captureDeviceFlashMode
        if isHighDefinitionModeEnabled {
            settings.photoQualityPrioritization = .quality
        }

        photoCaptureOutput?.capture(
            with: settings,
            outputSize: OutputSizeHelper.normalizedSize(
                for: cameraKit.activeInput.frameSize,
                aspectRatio: resolvedCaptureAspectRatio
            )
        ) { image, error in
            completion?(image, error)
        }
    }

    /// Configures the photo output to be ready to capture a new photo.
    fileprivate func configurePhotoCapture() {
        guard photoCaptureOutput == nil else { return }

        // Add AVCapturePhotoOutput to capture session
        let avPhotoCaptureOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(avPhotoCaptureOutput) {
            captureSession.addOutput(avPhotoCaptureOutput)
        }
        nativePhotoCaptureOutput = avPhotoCaptureOutput
        updatePhotoQualityPrioritization()
        photoCaptureOutput = PhotoCaptureOutput(capturePhotoOutput: avPhotoCaptureOutput)
        if let photoCaptureOutput {
            cameraKit.add(output: photoCaptureOutput)
        }
    }

    // MARK: Offline Media Input

    /// Replaces the live camera feed with a static image as the CameraKit input source.
    open func loadOfflineImage(_ image: UIImage, completion: (() -> Void)? = nil) {
        let input = StaticImageInput(image: image, frameDuration: CMTime(value: 1, timescale: 30))
        switchToOfflineInput(input, completion: completion)
    }

    /// Replaces the live camera feed with a looping video asset as the CameraKit input source.
    open func loadOfflineVideoAsset(_ asset: AVAsset, audioEnabled: Bool = true, completion: (() -> Void)? = nil) {
        let input = VideoAssetInput(asset: asset, audioEnabled: audioEnabled)
        switchToOfflineInput(input, completion: completion)
    }

    private func switchToOfflineInput(_ input: Input, completion: (() -> Void)?) {
        let shouldReapplyLenses = !readLensState { desiredLensStack.applied.isEmpty }

        captureSessionQueue.async { [weak self] in
            guard let self else { return }

            self.cameraKit.activeInput.stopRunning()
            self.captureSession.stopRunning()
            self.cameraKit.stop { [weak self] in
                guard let self else { return }

                let dataProvider = self.configureDataProvider()
                let arInput = ARSessionInput()
                self.cameraKit.start(
                    input: input,
                    arInput: arInput,
                    cameraPosition: self.cameraPosition,
                    videoOrientation: self.configuredOrientation,
                    dataProvider: dataProvider,
                    hintDelegate: self,
                    textInputContextProvider: self.configuredTextInputContextProvider,
                    agreementsPresentationContextProvider: self.configuredAgreementsPresentationContextProvider
                )
                input.startRunning()

                if shouldReapplyLenses {
                    self.reapplyCurrentLenses()
                }

                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }

    // MARK: LensRepositoryGroupObserver

    open func repository(_ repository: LensRepository, didUpdateLenses lenses: [Lens], forGroupID groupID: String) {
        // prefetch lens content (don't prefetch bundled since content is local already)
        if !groupID.contains(SCCameraKitLensRepositoryBundledGroup) {
            prefetchResourceQueue.async { [weak self] in
                guard let self, self.activePrefetchGroupIDs.contains(groupID) else { return }
                self.releasePrefetchResources(forGroupID: groupID)
                self.prefetchTasksByGroupID[groupID] = self.cameraKit.lenses.prefetcher.prefetch(
                    lenses: lenses,
                    completion: nil
                )
                self.prefetchedLensesByGroupID[groupID] = lenses
                for lens in lenses {
                    self.cameraKit.lenses.prefetcher.addStatusObserver(self, lens: lens)
                }
            }
        }

        publishCarouselLenses()
    }

    open func repository(
        _ repository: LensRepository, didFailToUpdateLensesForGroupID groupID: String, error: Error?
    ) {
    }

    private func publishCarouselLenses() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.uiDelegate?.cameraController(self, updatedLenses: self.carouselLenses)
        }
    }

    // MARK: LensPrefetcherObserver

    public func prefetcher(_ prefetcher: LensPrefetcher, didUpdate lens: Lens, status: LensFetchStatus) {
        guard appliedLenses.contains(where: { lensesMatch($0, lens) }) else {
            return
        }

        DispatchQueue.main.async {
            if status == .loading {
                self.uiDelegate?.cameraControllerRequestedActivityIndicatorShow(self)
            } else {
                self.uiDelegate?.cameraControllerRequestedActivityIndicatorHide(self)
            }
        }
    }
    
    // MARK: Recorder 
    
    /// Configures the recorder to be ready to record a new video.
    open func configureRecorder() {
        configureRecorder(using: resolvedRecordingSetup().configuration)
    }

    private func configureRecorder(using configuration: RecordingConfiguration) {
        if let old = recorder {
            old.finishRecording(completion: nil)
            cameraKit.remove(output: old.output)
        }

        do {
            recorder = try Recorder(
                url: URL(fileURLWithPath: "\(NSTemporaryDirectory())\(UUID().uuidString).mp4"),
                orientation: cameraKit.activeInput.frameOrientation,
                configuration: configuration
            )
        } catch {
            recorder = nil
            print("[CameraKit Recorder] configuration failed: \(error.localizedDescription)")
        }
        if let recorder {
            cameraKit.add(output: recorder.output)
        }
    }

    /// Begin recording video.
    open func startRecording() {
        guard let device = cameraInputDevice else {
            return
        }
        do {
            try device.lockForConfiguration()
            if device.isTorchModeSupported(flashState.captureDeviceTorchMode) {
                device.torchMode = flashState.captureDeviceTorchMode
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to configure torch mode.")
            return
        }

        uiDelegate?.cameraControllerRequestedSnapAttributionViewHide(self)
        let setup = resolvedRecordingSetup()
        activateRecordingResolutionOutput(using: setup)
        configureRecorder(using: setup.configuration)
        guard let recorder else {
            deactivateRecordingResolutionOutput()
            return
        }
        recorder.startRecording()
    }

    /// Cancel recording video.
    open func cancelRecording() {
        finishRecording(completion: nil)
    }

    /// Finish recording the video.
    /// - Parameter completion: completion to be called with a URL to the recorded video or an error.
    open func finishRecording(completion: ((URL?, Error?) -> Void)?) {
        guard let recorder else {
            deactivateRecordingResolutionOutput()
            DispatchQueue.main.async {
                completion?(nil, nil)
            }
            return
        }
        self.recorder = nil
        recorder.finishRecording { url, error in
            DispatchQueue.main.async {
                completion?(url, error)
            }
        }
        cameraKit.remove(output: recorder.output)
        deactivateRecordingResolutionOutput()
        captureSessionQueue.async { [weak self] in
            guard let device = self?.cameraInputDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            } catch {
                print("[CameraKit] Failed to lock device for configuration when trying to disable camera torch")
            }
        }
        uiDelegate?.cameraControllerRequestedSnapAttributionViewShow(self)
    }

    private typealias RecordingSetup = (
        configuration: RecordingConfiguration,
        inputSize: CGSize,
        lensActive: Bool
    )

    private func resolvedRecordingSetup() -> RecordingSetup {
        let configured = recordingConfiguration ?? RecordingConfiguration(
            outputSize: cameraKit.activeInput.frameSize,
            framesPerSecond: 30,
            highDefinitionModeEnabled: isHighDefinitionModeEnabled
        )
        let inputSize = cameraKit.activeInput.frameSize
        let sourceSize = inputSize == .zero ? configured.outputSize : inputSize
        let lensActive = !appliedLenses.isEmpty
        let outputSize = LensRenderingResolution.fullResolution(for: sourceSize)
        let videoCodec = resolvedRecordingVideoCodec()
        return (
            configuration: configured
                .replacingOutputSize(outputSize)
                .replacingVideoCodec(videoCodec),
            inputSize: inputSize,
            lensActive: lensActive
        )
    }

    private func resolvedRecordingVideoCodec() -> AVVideoCodecType {
        guard let videoOutput = captureSession.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first else {
            let codec = RecordingVideoCodecResolver.resolve(recommendedSettings: nil, availableCodecs: [])
            print("[CameraKit Recorder] no active video data output; falling back to \(codec.rawValue)")
            return codec
        }

        let recommendedSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        let availableCodecs = videoOutput.availableVideoCodecTypesForAssetWriter(writingTo: .mp4)
        let codec = RecordingVideoCodecResolver.resolve(
            recommendedSettings: recommendedSettings,
            availableCodecs: availableCodecs
        )
        print("[CameraKit Recorder] camera-default codec=\(codec.rawValue)")
        return codec
    }

    private func activateRecordingResolutionOutput(using setup: RecordingSetup) {
        refreshHighDefinitionLensRendering()
        recordingResolutionOutput.setOutputResolution(setup.configuration.outputSize)
        if !recordingResolutionOutputAttached {
            cameraKit.add(output: recordingResolutionOutput)
            recordingResolutionOutputAttached = true
        }
        print(
            "[CameraKit Recorder] render input=\(Int(setup.inputSize.width))x\(Int(setup.inputSize.height)) "
                + "lensActive=\(setup.lensActive) "
                + "output=\(Int(setup.configuration.outputSize.width))x\(Int(setup.configuration.outputSize.height)) "
                + "codec=\(setup.configuration.videoCodec.rawValue) "
                + "bitrate=\(setup.configuration.videoBitRate) "
                + "hdRequested=\(isHighDefinitionLensRenderingEnabled) "
                + "hdRuntime=\(isHighDefinitionLensRenderingActive)"
        )
    }

    private func deactivateRecordingResolutionOutput() {
        if recordingResolutionOutputAttached {
            cameraKit.remove(output: recordingResolutionOutput)
            recordingResolutionOutputAttached = false
            recordingResolutionOutput.setOutputResolution(.zero)
        }
    }

    private func refreshHighDefinitionLensRendering() {
        let lensActive = !appliedLenses.isEmpty
        guard let outputSize = HighDefinitionLensRenderingPolicy.overrideSize(
            enabled: isHighDefinitionLensRenderingEnabled,
            lensActive: lensActive,
            sourceSize: recordingConfiguration?.outputSize ?? cameraKit.activeInput.frameSize
        ) else {
            clearHighDefinitionLensRenderingOverride()
            return
        }

        isHighDefinitionLensRenderingActive = SCCameraKitSetHighDefinitionRenderingResolution(
            cameraKit.lenses.processor,
            Int(outputSize.width),
            Int(outputSize.height)
        )
        highDefinitionLensRenderingSize = isHighDefinitionLensRenderingActive ? outputSize : nil
    }

    private func clearHighDefinitionLensRenderingOverride() {
        guard isHighDefinitionLensRenderingActive else { return }
        _ = SCCameraKitSetHighDefinitionRenderingResolution(cameraKit.lenses.processor, 0, 0)
        isHighDefinitionLensRenderingActive = false
        highDefinitionLensRenderingSize = nil
    }

    // MARK: Live Streaming

    /// Streams CameraKit's post-lens frame output to a WebSocket endpoint.
    open func startWebSocketStreaming(
        to url: URL,
        requestHeaders: [String: String] = [:],
        framesPerSecond: Double = 8,
        jpegQuality: CGFloat = 0.58,
        maxDimension: CGFloat = 540
    ) {
        stopWebSocketStreaming()

        let output = CameraKitWebSocketStreamOutput(
            url: url,
            requestHeaders: requestHeaders,
            framesPerSecond: framesPerSecond,
            jpegQuality: jpegQuality,
            maxDimension: maxDimension
        )
        streamOutput = output
        cameraKit.add(output: output)
        output.startStreaming()
    }

    /// Stops the active live web preview stream.
    open func stopWebSocketStreaming() {
        guard let output = streamOutput else { return }
        output.stopStreaming()
        cameraKit.remove(output: output)
        streamOutput = nil
    }

    // MARK: Lens Application

    /// Supplies the dedicated Retouch Lens used by the top-right Retouch control.
    /// The Lens is excluded from the carousel and occupies the first composite-Lens layer.
    public func configureRetouchLens(_ lens: Lens?, completion: ((Bool) -> Void)? = nil) {
        configureRetouchLenses(
            standard: lens,
            machineLearning: nil,
            selected: .standard,
            completion: completion
        )
    }

    /// Supplies both Retouch implementations used by the top-right Retouch control.
    public func configureRetouchLenses(
        standard: Lens?,
        machineLearning: Lens?,
        selected: RetouchLensVariant = .standard,
        completion: ((Bool) -> Void)? = nil
    ) {
        let options = RetouchLensOptions(standard: standard, machineLearning: machineLearning)
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            self.configuredRetouchOptions = options
            let resolvedVariant = options.resolvedVariant(preferred: selected)
            self.selectedRetouchVariant = resolvedVariant ?? selected
            self.configurePermanentLensOnQueue(
                resolvedVariant.flatMap { options[$0] },
                control: .retouch,
                completion: completion
            )
        }
    }

    /// Replaces the Retouch layer with another configured implementation without disturbing other Lenses.
    public func setRetouchLensVariant(
        _ variant: RetouchLensVariant,
        completion: ((Bool) -> Void)? = nil
    ) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped, let lens = self.configuredRetouchOptions[variant] else {
                completion?(false)
                return
            }
            self.selectedRetouchVariant = variant
            self.configurePermanentLensOnQueue(lens, control: .retouch, completion: completion)
        }
    }

    /// Enables or disables the dedicated Retouch layer without changing the pinned or selected Lenses.
    public func setRetouchEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        setPermanentLensEnabled(enabled, control: .retouch, completion: completion)
    }

    /// Supplies the dedicated Rhinoplasty Lens used by the top-right Rhinoplasty control.
    /// The Lens is excluded from the carousel and occupies the second composite-Lens layer.
    public func configureRhinoplastyLens(_ lens: Lens?, completion: ((Bool) -> Void)? = nil) {
        configurePermanentLens(lens, control: .rhinoplasty, completion: completion)
    }

    /// Enables or disables the dedicated Rhinoplasty layer without changing other Lens layers.
    public func setRhinoplastyEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        setPermanentLensEnabled(enabled, control: .rhinoplasty, completion: completion)
    }

    /// Apply a specified lens.
    /// - Parameters:
    ///   - lens: selected lens
    ///   - completion: callback on completion with success/failure
    public func applyLens(_ lens: Lens, completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            self.desiredLensStack.select(lens, matches: self.lensesMatch)
            self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
        }
    }

    /// Configures the post-Lens pixel dimensions and frame rate used by subsequent recordings.
    open func setRecordingConfiguration(
        outputSize: CGSize,
        framesPerSecond: Int,
        videoBitRate: Int? = nil
    ) {
        recordingConfiguration = RecordingConfiguration(
            outputSize: outputSize,
            framesPerSecond: framesPerSecond,
            videoBitRate: videoBitRate,
            highDefinitionModeEnabled: isHighDefinitionModeEnabled
        )
        refreshHighDefinitionLensRendering()
    }

    /// Refreshes Camera Kit's cached input dimensions after the host changes AVCaptureDevice.activeFormat.
    open func refreshActiveInputAttributes() {
        // Camera Kit declares activeInput as nonnull, but it is not initialized until start() completes.
        guard captureSession.isRunning else { return }
        cameraKit.activeInput.setVideoOrientation(configuredOrientation)
        refreshHighDefinitionLensRendering()
    }

    /// Enables or disables native HD capture policy, photo quality, recording bitrate, and Lens rendering.
    open func setHighDefinitionModeEnabled(_ enabled: Bool) {
        guard isHighDefinitionLensRenderingEnabled != enabled else {
            updatePhotoQualityPrioritization()
            refreshHighDefinitionLensRendering()
            return
        }

        isHighDefinitionLensRenderingEnabled = enabled
        recordingConfiguration = recordingConfiguration?.replacingHighDefinitionModeEnabled(enabled)
        updatePhotoQualityPrioritization()
        refreshHighDefinitionLensRendering()
        notifyControlsDidChange()
    }

    /// Compatibility entry point for hosts built against the original HD Lens-rendering toggle.
    open func setHighDefinitionLensRenderingEnabled(_ enabled: Bool) {
        setHighDefinitionModeEnabled(enabled)
    }

    private func updatePhotoQualityPrioritization() {
        nativePhotoCaptureOutput?.maxPhotoQualityPrioritization = isHighDefinitionModeEnabled
            ? .quality
            : .balanced
    }
    
    public func warmupLens(_ lens: Lens, completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, let processor = self.cameraKit.lenses.processor else {
                completion?(false)
                return
            }
            processor.warmup(lens: lens, launchData: self.launchData(for: lens)) { success in
                if success {
                    print("\(lens.name ?? "Unnamed") (\(lens.id)) warmed up")
                } else {
                    print("Lens failed to warmup")
                }
                completion?(success)
            }
        }
    }

    /// Clears the selected top Lens. A pinned base remains applied.
    ///   - willReapply: if true, physically clears Camera Kit while retaining the full desired stack for `reapplyCurrentLenses()`.
    ///   - completion: callback on completion with success/failure
    public func clearLens(willReapply: Bool = false, completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            if willReapply {
                self.enqueueLensOperationOnQueue(.clear(preserveStack: true, completion: completion))
                return
            }

            self.desiredLensStack.clearTop()
            if self.desiredLensStack.applied.isEmpty {
                self.enqueueLensOperationOnQueue(.clear(preserveStack: false, completion: completion))
            } else {
                self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
            }
        }
    }

    /// Clears every Lens and removes any pinned base state.
    public func clearAllLenses(completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            self.desiredLensStack.reset()
            self.retouchRequestedEnabled = false
            self.rhinoplastyRequestedEnabled = false
            self.notifyControlsDidChange()
            self.enqueueLensOperationOnQueue(.clear(preserveStack: false, completion: completion))
        }
    }

    /// Pins the confirmed current Lens as the session's base layer.
    public func pinCurrentLensAsBase(completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            guard self.desiredLensStack.pinCurrent() else {
                completion?(false)
                return
            }
            self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
        }
    }

    /// Makes the confirmed current top Lens the base layer, replacing an existing pinned base if necessary.
    public func setCurrentLensAsBase(completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            guard self.desiredLensStack.replaceBaseWithCurrent() else {
                completion?(false)
                return
            }
            self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
        }
    }

    /// Removes the pinned role. An active top Lens remains as the sole Lens.
    public func unpinBaseLens(completion: ((Bool) -> Void)? = nil) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped, self.desiredLensStack.pinnedBase != nil else {
                completion?(false)
                return
            }
            self.desiredLensStack.unpin()
            if self.desiredLensStack.applied.isEmpty {
                self.enqueueLensOperationOnQueue(.clear(preserveStack: false, completion: completion))
            } else {
                self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
            }
        }
    }

    /// Removes a Lens from either active role using its stable repository identity.
    public func removeLensFromActiveStack(
        id: String,
        groupID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }
            let identity = LensLayerIdentity(id: id, groupID: groupID)
            let before = self.desiredLensStack
            self.desiredLensStack.remove { self.identity(for: $0) == identity }
            guard !self.lensStacksMatch(before, self.desiredLensStack) else {
                completion?(true)
                return
            }
            if self.desiredLensStack.applied.isEmpty {
                self.enqueueLensOperationOnQueue(.clear(preserveStack: false, completion: completion))
            } else {
                self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: completion))
            }
        }
    }

    /// Returns whether the supplied Lens is the confirmed pinned base.
    public func isPinnedBase(_ lens: Lens) -> Bool {
        readLensState {
            activeLensStack.pinnedBase.map { lensesMatch($0, lens) } ?? false
        }
    }

    /// Reapplies the complete desired Lens stack.
    public func reapplyCurrentLenses() {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped, !self.desiredLensStack.applied.isEmpty else { return }
            self.enqueueLensOperationOnQueue(.apply(stack: self.desiredLensStack, completion: nil))
        }
    }

    /// Compatibility alias for callers written against the single-Lens controller.
    public func reapplyCurrentLens() {
        reapplyCurrentLenses()
    }

    /// Sets app-provided launch data that custom lenses can read when they are applied.
    ///
    /// This is the host-app pathway for custom Lens Studio scene controls, such as a Lens script
    /// that maps `afterglow_lighting` or `afterglow_shadows` to an orthographic camera or light.
    public func setLensLaunchDataOverrides(_ overrides: [String: String], reapplyCurrentLens: Bool = false) {
        lensLaunchDataOverrides = overrides
        if reapplyCurrentLens {
            reapplyCurrentLenses()
        }
    }

    // MARK: Adjustments Application

    /// Enables the tone map adjustment.
    /// - Returns: Float representing the intensity of the tone map effect.
    /// - Note: Before calling this function, check whether or not the adjustment is available for the device. See `isToneMapAdjustmentAvailable`.
    public func enableToneMapAdjustment() -> Float? {
        if toneMapController == nil {
            toneMapController = try? cameraKit.adjustments.processor?.apply(ToneMapAdjustment())
                as? ToneMapAdjustmentController
        }
        guard let toneMapController else { return nil }

        let amount = toneMapAdjustmentAmount > 0 ? toneMapAdjustmentAmount : max(Double(toneMapController.amount), 0.5)
        toneMapAdjustmentAmount = min(max(amount, 0), 1)
        toneMapController.amount = toneMapAdjustmentAmount
        notifyControlsDidChange()
        return Float(toneMapAdjustmentAmount)
    }

    /// Disables the tone map adjustment.
    public func disableToneMapAdjustment() {
        if let toneMapController {
            cameraKit.adjustments.processor?.remove(toneMapController)
            self.toneMapController = nil
        }
        toneMapAdjustmentAmount = 0
        notifyControlsDidChange()
    }

    /// Sets the tone map adjustment amount used for shadow/highlight balancing.
    ///
    /// A value of `0` disables the adjustment. Values above `0` enable Camera Kit's native tone mapping.
    public func setToneMapAdjustmentAmount(_ amount: Double) {
        let clampedAmount = min(max(amount, 0), 1)
        toneMapAdjustmentAmount = clampedAmount

        DispatchQueue.main.async { [weak self] in
            self?.applyPreferredToneMapAdjustment()
            self?.notifyControlsDidChange()
        }
    }

    /// Enables the portrait adjustment.
    /// - Returns: Float representing the intensity of the portrait blur effect.
    /// - Note: Before calling this function, check whether or not the adjustment is available for the device. See `isPortraitAdjustmentAvailable`.
    public func enablePortraitAdjustment() -> Float? {
        if portraitController == nil {
            portraitController = try? cameraKit.adjustments.processor?.apply(PortraitAdjustment())
                as? PortraitAdjustmentController
        }
        guard let portraitController else { return nil }

        let blur = portraitAdjustmentBlur > 0 ? portraitAdjustmentBlur : max(Double(portraitController.blur), 0.5)
        portraitAdjustmentBlur = min(max(blur, 0), 1)
        portraitController.blur = portraitAdjustmentBlur
        notifyControlsDidChange()
        return Float(portraitAdjustmentBlur)
    }

    /// Disables the portrait adjustment.
    public func disablePortraitAdjustment() {
        if let portraitController {
            cameraKit.adjustments.processor?.remove(portraitController)
            self.portraitController = nil
        }
        portraitAdjustmentBlur = 0
        notifyControlsDidChange()
    }

    /// Sets Camera Kit's pre-Lens portrait blur. Zero disables the adjustment.
    public func setPortraitAdjustmentBlur(_ blur: Double) {
        portraitAdjustmentBlur = min(max(blur, 0), 1)
        DispatchQueue.main.async { [weak self] in
            self?.applyPreferredPortraitAdjustment()
            self?.notifyControlsDidChange()
        }
    }

    /// Sets the exposure target bias on the active capture device.
    ///
    /// This keeps lighting changes in the camera input before Camera Kit processes frames for lenses.
    public func setExposureTargetBias(_ bias: Float) {
        preferredExposureTargetBias = bias
        captureSessionQueue.async { [weak self] in
            self?.applyPreferredExposureTargetBias()
        }
    }

    /// Sets warmth and tint on the active capture device.
    ///
    /// Values should be in the range `-1...1`. Passing `0, 0` restores continuous auto white balance.
    public func setWhiteBalanceAdjustment(warmth: Float, tint: Float) {
        preferredWhiteBalanceWarmth = min(max(warmth, -1), 1)
        preferredWhiteBalanceTint = min(max(tint, -1), 1)
        captureSessionQueue.async { [weak self] in
            self?.applyPreferredWhiteBalanceAdjustment()
        }
    }

    /// Sets the aspect ratio used by Camera Kit photo and video outputs.
    public func setCaptureAspectRatio(_ aspectRatio: CGFloat?) {
        if let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            captureAspectRatio = aspectRatio
        } else {
            captureAspectRatio = nil
        }
    }

    /// Selects the rear camera input. Ultra-wide falls back to automatic when unavailable.
    public func setBackCameraDeviceMode(_ mode: BackCameraDeviceMode) {
        guard backCameraDeviceMode != mode else { return }
        backCameraDeviceMode = mode
        guard cameraPosition == .back else {
            notifyControlsDidChange()
            return
        }
        captureSessionQueue.async { [weak self] in
            guard let self else { return }
            self.replaceVideoInputIfNeeded(for: .back)
        }
    }

    // MARK: LensHintDelegate

    public func lensProcessor(
        _ lensProcessor: LensProcessor, shouldDisplayHint hint: String, for lens: Lens, autohide: Bool
    ) {
        uiDelegate?.cameraController(self, requestedHintDisplay: hint, for: lens, autohide: autohide)
    }

    public func lensProcessor(_ lensProcessor: LensProcessor, shouldHideAllHintsFor lens: Lens) {
        uiDelegate?.cameraController(self, requestedHintHideFor: lens)
    }

    // MARK: MediaPickerViewDelegate

    public func mediaPickerView(_ mediaPickerView: MediaPickerView, selectedAsset: LensMediaPickerProviderAsset) {
        mediaPickerView.showLoadingIndicator(for: selectedAsset)
        lensMediaProvider.loadAndApplyOriginalMedia(from: selectedAsset) {
            mediaPickerView.hideLoadingIndicator(for: selectedAsset)
        }
    }

    // MARK: AdjustmentsControlViewDelegate

    public func adjustmentControlView(_ control: AdjustmentControlView, sliderValueChanged value: Double) {
        switch AdjustmentControlView.Variant(rawValue: control.tag) {
        case .tone: setToneMapAdjustmentAmount(value)
        case .portrait: setPortraitAdjustmentBlur(value)
        default: break
        }
    }

    // MARK: - Private API

    // MARK: Private vars

    /// Controller for adjusting the applied tone map adjustment.
    private var toneMapController: ToneMapAdjustmentController?

    /// Controller for adjusting the applied portrait adjustment.
    private var portraitController: PortraitAdjustmentController?

    /// App-provided launch data merged into the selected lens's vendor data.
    private var lensLaunchDataOverrides: [String: String] = [:]

    /// Temporary state that holds the starting point for the last zoom level
    /// Since pinching is a relative operation, we need to keep whatever it was left at last to compare.
    private var lastZoomLevel: CGFloat = 1

    /// State that holds the last flash mode for when the front camera flash was enabled.
    /// Used for selecting the correct flash mode when flipping from the back to the front camera with flash enabled.
    private var lastFrontFlashMode: FlashMode?

    /// Temporary state that holds the brightness that should be restored after the ring light is disabled.
    public var brightnessToRestore: CGFloat?

    /// serial queue used to apply/clear lenses
    fileprivate let lensQueue = DispatchQueue(label: "com.snap.camerakit.sample.lensqueue", qos: .userInitiated)
    private let lensQueueKey = DispatchSpecificKey<Void>()
    private var desiredLensStack = LensLayerStack<Lens>()
    private var activeLensStack = LensLayerStack<Lens>()
    private var configuredRetouchLens: Lens?
    private var configuredRetouchOptions = RetouchLensOptions<Lens>(standard: nil, machineLearning: nil)
    private var selectedRetouchVariant: RetouchLensVariant = .standard
    private var retouchRequestedEnabled = false
    private var configuredRhinoplastyLens: Lens?
    private var rhinoplastyRequestedEnabled = false

    private enum PermanentLensControl {
        case retouch
        case rhinoplasty
    }

    private enum PendingLensOperation {
        case apply(stack: LensLayerStack<Lens>, completion: ((Bool) -> Void)?)
        case clear(preserveStack: Bool, completion: ((Bool) -> Void)?)

        func complete(_ success: Bool) {
            switch self {
            case let .apply(_, completion), let .clear(_, completion):
                completion?(success)
            }
        }
    }

    private var pendingLensOperation: PendingLensOperation?
    private var lensOperationInFlight = false
    private var lensOperationsStopped = false

    /// The current camera input device
    fileprivate var cameraInputDevice: AVCaptureDevice? {
        captureSession.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first(where: { $0.hasMediaType(.video) })
    }

    fileprivate var isAdjustingExposureObservation: NSKeyValueObservation?

    fileprivate var isAdjustingFocusObservation: NSKeyValueObservation?

    private func configurePermanentLens(
        _ lens: Lens?,
        control: PermanentLensControl,
        completion: ((Bool) -> Void)?
    ) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }

            self.configurePermanentLensOnQueue(lens, control: control, completion: completion)
        }
    }

    private func configurePermanentLensOnQueue(
        _ lens: Lens?,
        control: PermanentLensControl,
        completion: ((Bool) -> Void)?
    ) {
        dispatchPrecondition(condition: .onQueue(lensQueue))

        let previousLens = configuredLens(for: control)
        let hadActiveLayer = previousLens.map { previous in
            activeLensStack.persistentBases.contains { active in
                lensesMatch(active, previous)
            }
        } ?? false
        setConfiguredLens(lens, for: control)
        updateDesiredPersistentBases()

        let finish = { [weak self] (success: Bool) in
            guard let self else {
                completion?(false)
                return
            }
            if !success {
                self.setPermanentLensRequested(
                    self.activePersistentLens(matching: self.configuredLens(for: control)) != nil,
                    for: control
                )
                self.updateDesiredPersistentBases()
            }
            self.notifyControlsDidChange()
            completion?(success)
        }

        if isPermanentLensRequested(control) || hadActiveLayer {
            applyDesiredLensStackIfProcessorAvailable(completion: finish)
        } else {
            finish(true)
        }

        publishCarouselLenses()
        notifyControlsDidChange()
    }

    private func setPermanentLensEnabled(
        _ enabled: Bool,
        control: PermanentLensControl,
        completion: ((Bool) -> Void)?
    ) {
        lensQueue.async { [weak self] in
            guard let self, !self.lensOperationsStopped else {
                completion?(false)
                return
            }

            self.setPermanentLensRequested(enabled, for: control)
            self.updateDesiredPersistentBases()
            if enabled, self.configuredLens(for: control) == nil {
                self.notifyControlsDidChange()
                completion?(false)
                return
            }

            self.notifyControlsDidChange()
            self.applyDesiredLensStackIfProcessorAvailable { [weak self] success in
                guard let self else {
                    completion?(false)
                    return
                }
                if !success {
                    self.setPermanentLensRequested(
                        self.activePersistentLens(matching: self.configuredLens(for: control)) != nil,
                        for: control
                    )
                    self.updateDesiredPersistentBases()
                }
                self.notifyControlsDidChange()
                completion?(success)
            }
        }
    }

    private func configuredLens(for control: PermanentLensControl) -> Lens? {
        switch control {
        case .retouch: return configuredRetouchLens
        case .rhinoplasty: return configuredRhinoplastyLens
        }
    }

    private func setConfiguredLens(_ lens: Lens?, for control: PermanentLensControl) {
        switch control {
        case .retouch: configuredRetouchLens = lens
        case .rhinoplasty: configuredRhinoplastyLens = lens
        }
    }

    private func isPermanentLensRequested(_ control: PermanentLensControl) -> Bool {
        switch control {
        case .retouch: return retouchRequestedEnabled
        case .rhinoplasty: return rhinoplastyRequestedEnabled
        }
    }

    private func setPermanentLensRequested(_ enabled: Bool, for control: PermanentLensControl) {
        switch control {
        case .retouch: retouchRequestedEnabled = enabled
        case .rhinoplasty: rhinoplastyRequestedEnabled = enabled
        }
    }

    private func updateDesiredPersistentBases() {
        let layers = [
            retouchRequestedEnabled ? configuredRetouchLens : nil,
            rhinoplastyRequestedEnabled ? configuredRhinoplastyLens : nil,
        ].compactMap { $0 }
        desiredLensStack.setPersistentBases(layers)
    }

    private func activePersistentLens(matching configuredLens: Lens?) -> Lens? {
        guard let configuredLens else { return nil }
        return activeLensStack.persistentBases.first { lensesMatch($0, configuredLens) }
    }

    private func applyDesiredLensStackIfProcessorAvailable(completion: ((Bool) -> Void)?) {
        dispatchPrecondition(condition: .onQueue(lensQueue))
        guard cameraKit.lenses.processor != nil else {
            completion?(true)
            return
        }

        if desiredLensStack.applied.isEmpty {
            enqueueLensOperationOnQueue(.clear(preserveStack: false, completion: completion))
        } else {
            enqueueLensOperationOnQueue(.apply(stack: desiredLensStack, completion: completion))
        }
    }

    private func enqueueLensOperationOnQueue(_ operation: PendingLensOperation) {
        dispatchPrecondition(condition: .onQueue(lensQueue))
        pendingLensOperation?.complete(false)
        pendingLensOperation = operation
        startNextLensOperationIfNeeded()
    }

    private func startNextLensOperationIfNeeded() {
        guard !lensOperationsStopped, !lensOperationInFlight, let operation = pendingLensOperation else { return }
        pendingLensOperation = nil
        lensOperationInFlight = true

        guard let processor = cameraKit.lenses.processor else {
            switch operation {
            case let .apply(stack, _):
                if lensStacksMatch(desiredLensStack, stack) {
                    desiredLensStack = activeLensStack
                }
            case let .clear(preserveStack, _):
                if !preserveStack, desiredLensStack.applied.isEmpty {
                    desiredLensStack = activeLensStack
                }
            }
            finishLensOperation(operation, success: false)
            return
        }

        switch operation {
        case let .apply(stack, _):
            applyLensStack(stack, processor: processor) { [weak self] success in
                guard let self else {
                    operation.complete(false)
                    return
                }
                self.lensQueue.async {
                    guard !self.lensOperationsStopped else {
                        self.finishStoppedLensOperation(operation)
                        return
                    }
                    if success {
                        self.finishSuccessfulApply(stack, operation: operation)
                    } else if stack.applied.count >= 2, stack.selectedTop != nil {
                        self.restoreBaseAfterCompositeFailure(stack, processor: processor, operation: operation)
                    } else {
                        if self.lensStacksMatch(self.desiredLensStack, stack) {
                            self.desiredLensStack = self.activeLensStack
                        }
                        print("Lens failed to apply")
                        self.finishLensOperation(operation, success: false)
                    }
                }
            }
        case let .clear(preserveStack, _):
            processor.clear { [weak self] completed in
                guard let self else {
                    operation.complete(false)
                    return
                }
                self.lensQueue.async {
                    guard !self.lensOperationsStopped else {
                        self.finishStoppedLensOperation(operation)
                        return
                    }
                    if completed, !preserveStack, self.desiredLensStack.applied.isEmpty {
                        self.activeLensStack.reset()
                        self.publishLensStackDidChange()
                    } else if !completed, !preserveStack, self.desiredLensStack.applied.isEmpty {
                        self.desiredLensStack = self.activeLensStack
                    }
                    self.finishLensOperation(operation, success: completed)
                }
            }
        }
    }

    private func finishLensOperation(_ operation: PendingLensOperation, success: Bool) {
        lensOperationInFlight = false
        operation.complete(success)
        startNextLensOperationIfNeeded()
    }

    private func finishStoppedLensOperation(_ operation: PendingLensOperation) {
        lensOperationInFlight = false
        operation.complete(false)
    }

    private func stopPendingLensOperations() {
        lensQueue.async { [weak self] in
            guard let self else { return }
            self.lensOperationsStopped = true
            self.pendingLensOperation?.complete(false)
            self.pendingLensOperation = nil
        }
    }

    private func applyLensStack(
        _ stack: LensLayerStack<Lens>,
        processor: LensProcessor,
        completion: @escaping (Bool) -> Void
    ) {
        let lenses = stack.applied
        switch lenses.count {
        case 0:
            processor.clear(completion: completion)
        case 1:
            let lens = lenses[0]
            processor.apply(lens: lens, launchData: launchData(for: lens), completion: completion)
        default:
            let lensObjects: [Any] = lenses.map { $0 }
            let launchData = lenses.map(compositeLaunchData)
            SCCameraKitApplyCompositeLenses(
                processor,
                lensObjects,
                launchData,
                completion
            )
        }
    }

    private func finishSuccessfulApply(_ stack: LensLayerStack<Lens>, operation: PendingLensOperation) {
        let isNewestRequest = lensStacksMatch(desiredLensStack, stack)
        if isNewestRequest {
            activeLensStack = stack
            if let lens = stack.current {
                print("\(lensName(lens)) (\(lens.id)) Applied")
                DispatchQueue.main.async { [weak self] in
                    self?.changeCameraPosition(with: lens.facingPreference)
                }
            }
            publishLensStackDidChange()
        }
        finishLensOperation(operation, success: true)
    }

    private func restoreBaseAfterCompositeFailure(
        _ failedStack: LensLayerStack<Lens>,
        processor: LensProcessor,
        operation: PendingLensOperation
    ) {
        var lowerLayers = failedStack
        lowerLayers.clearTop()
        guard let restoredLens = lowerLayers.current ?? lowerLayers.persistentBases.last else {
            finishLensOperation(operation, success: false)
            return
        }

        applyLensStack(lowerLayers, processor: processor) { [weak self] restored in
            guard let self else {
                operation.complete(false)
                return
            }
            self.lensQueue.async {
                guard !self.lensOperationsStopped else {
                    self.finishStoppedLensOperation(operation)
                    return
                }
                if restored {
                    self.activeLensStack = lowerLayers
                    if self.lensStacksMatch(self.desiredLensStack, failedStack) {
                        self.desiredLensStack = lowerLayers
                        self.publishLensStackDidChange()
                    }
                    print(
                        "Composite Lens apply failed; restored lower Lens layers through "
                            + "\(self.lensName(restoredLens)) (\(restoredLens.id))"
                    )
                    self.finishLensOperation(operation, success: false)
                } else if
                    self.lensStacksMatch(self.desiredLensStack, failedStack),
                    let top = failedStack.selectedTop
                {
                    self.applyTopAfterUnavailableBase(
                        top,
                        failedStack: failedStack,
                        processor: processor,
                        operation: operation
                    )
                } else {
                    if self.lensStacksMatch(self.desiredLensStack, failedStack) {
                        self.desiredLensStack = self.activeLensStack
                    }
                    print("Composite Lens apply and pinned base restore both failed")
                    self.finishLensOperation(operation, success: false)
                }
            }
        }
    }

    private func applyTopAfterUnavailableBase(
        _ top: Lens,
        failedStack: LensLayerStack<Lens>,
        processor: LensProcessor,
        operation: PendingLensOperation
    ) {
        processor.apply(lens: top, launchData: launchData(for: top)) { [weak self] applied in
            guard let self else {
                operation.complete(false)
                return
            }
            self.lensQueue.async {
                guard !self.lensOperationsStopped else {
                    self.finishStoppedLensOperation(operation)
                    return
                }
                if applied {
                    var topOnly = LensLayerStack<Lens>()
                    topOnly.select(top, matches: self.lensesMatch)
                    self.activeLensStack = topOnly
                    if self.lensStacksMatch(self.desiredLensStack, failedStack) {
                        self.desiredLensStack = topOnly
                        self.publishLensStackDidChange()
                    }
                    print("Pinned base unavailable; applied top Lens \(self.lensName(top)) (\(top.id)) alone")
                } else if self.lensStacksMatch(self.desiredLensStack, failedStack) {
                    self.desiredLensStack = self.activeLensStack
                    print("Composite Lens, pinned base, and top Lens apply all failed")
                }
                self.finishLensOperation(operation, success: false)
            }
        }
    }

    private func publishLensStackDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshHighDefinitionLensRendering()
            self.uiDelegate?.cameraControllerLensStackDidChange(self)
        }
    }

    private func readLensState<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: lensQueueKey) != nil {
            return body()
        }
        return lensQueue.sync(execute: body)
    }

    private func lensesMatch(_ lhs: Lens, _ rhs: Lens) -> Bool {
        identity(for: lhs) == identity(for: rhs)
    }

    private func identity(for lens: Lens) -> LensLayerIdentity {
        LensLayerIdentity(id: lens.id, groupID: lens.groupId)
    }

    private func lensStacksMatch(_ lhs: LensLayerStack<Lens>, _ rhs: LensLayerStack<Lens>) -> Bool {
        lhs.persistentBases.count == rhs.persistentBases.count
            && zip(lhs.persistentBases, rhs.persistentBases).allSatisfy {
                lensesMatch($0.0, $0.1)
            }
            && optionalLensesMatch(lhs.pinnedBase, rhs.pinnedBase)
            && optionalLensesMatch(lhs.selectedTop, rhs.selectedTop)
    }

    private func optionalLensesMatch(_ lhs: Lens?, _ rhs: Lens?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lensesMatch(lhs, rhs)
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func lensName(_ lens: Lens) -> String {
        let name = lens.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? lens.id : name
    }

    private func compositeLaunchData(for lens: Lens) -> Any {
        guard !lens.vendorData.isEmpty || !lensLaunchDataOverrides.isEmpty else {
            return NSNull()
        }
        return launchData(for: lens)
    }

    private func releasePrefetchResources(forGroupID groupID: String) {
        prefetchTasksByGroupID.removeValue(forKey: groupID)?.cancel()
        let lenses = prefetchedLensesByGroupID.removeValue(forKey: groupID) ?? []
        for lens in lenses {
            cameraKit.lenses.prefetcher.removeStatusObserver(self, lens: lens)
        }
    }

    private func releaseAllPrefetchResources() {
        let groupIDs = Set(prefetchTasksByGroupID.keys).union(prefetchedLensesByGroupID.keys)
        for groupID in groupIDs {
            releasePrefetchResources(forGroupID: groupID)
        }
        activePrefetchGroupIDs.removeAll()
    }
}

// MARK: Camera Pipeline Configuration

private extension CameraController {
    /// Configures the capture session.
    func configureCaptureSession() {
        captureSession.beginConfiguration()
        configureDevice(for: .video)
        captureSession.commitConfiguration()
    }

    /// Prompts the user for access, and then calls a completion closure. If the user has already granted access, calls the closure synchronously.
    /// - Parameter completion: the completion closure to call.
    func promptForAccessIfNeeded(completion: @escaping () -> Void) {
        guard
            AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
            || AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        else {
            completion()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { _ in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    /// Configures the device specified.
    /// - Parameter mediaType: the media type, audio or video
    func configureDevice(for mediaType: AVMediaType) {
        guard
            let device = mediaType == .video
            ? preferredVideoDevice(for: cameraPosition)
            : AVCaptureDevice.default(for: mediaType),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            return
        }
        captureSession.addInput(input)
    }

    func preferredVideoDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            if backCameraDeviceMode == .ultraWide,
               let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                return ultraWide
            }
            for deviceType in [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera] {
                if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                    return device
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    func replaceVideoInputIfNeeded(for position: AVCaptureDevice.Position) {
        guard
            let desiredDevice = preferredVideoDevice(for: position),
            cameraInputDevice?.uniqueID != desiredDevice.uniqueID,
            let replacementInput = try? AVCaptureDeviceInput(device: desiredDevice)
        else {
            notifyControlsDidChange()
            return
        }

        let currentInput = captureSession.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })

        captureSession.beginConfiguration()
        if let currentInput {
            captureSession.removeInput(currentInput)
        }
        if captureSession.canAddInput(replacementInput) {
            captureSession.addInput(replacementInput)
        } else if let currentInput, captureSession.canAddInput(currentInput) {
            captureSession.addInput(currentInput)
        }
        captureSession.commitConfiguration()

        applyPreferredExposureTargetBias()
        applyPreferredWhiteBalanceAdjustment()
        notifyControlsDidChange()
    }

    /// Directly sets the zoom level, if possible. Certain inputs may ignore calls to this function (eg: ARKit)
    private var zoomLevel: CGFloat {
        get {
            guard
                !(cameraKit.activeInput is ARInput),
                let device = cameraInputDevice
            else {
                return 1
            }
            return device.videoZoomFactor
        }
        set {
            guard
                !(cameraKit.activeInput is ARInput),
                let device = cameraInputDevice
            else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(1.0, min(newValue, device.activeFormat.videoMaxZoomFactor))
                device.unlockForConfiguration()
            } catch {
                print("[CameraKit] Failed to lock device for configuration when trying to adjust zoom level")
                return
            }
        }
    }

    private func applyPreferredExposureTargetBias() {
        guard let device = cameraInputDevice else {
            return
        }

        do {
            try device.lockForConfiguration()
            let clampedBias = min(max(preferredExposureTargetBias, device.minExposureTargetBias), device.maxExposureTargetBias)
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to adjust exposure bias")
        }
    }

    private func applyPreferredWhiteBalanceAdjustment() {
        guard let device = cameraInputDevice else {
            return
        }

        do {
            try device.lockForConfiguration()
            if abs(preferredWhiteBalanceWarmth) < 0.001, abs(preferredWhiteBalanceTint) < 0.001 {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
                return
            }

            let temperature = 5_000 + preferredWhiteBalanceWarmth * 3_000
            let tint = preferredWhiteBalanceTint * 75
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: temperature,
                tint: tint
            )
            let gains = device.deviceWhiteBalanceGains(for: values)
            device.setWhiteBalanceModeLocked(with: clampedWhiteBalanceGains(gains, for: device), completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to adjust white balance")
        }
    }

    private func clampedWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let maxGain = device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, 1), maxGain),
            greenGain: min(max(gains.greenGain, 1), maxGain),
            blueGain: min(max(gains.blueGain, 1), maxGain)
        )
    }

    private func applyPreferredToneMapAdjustment() {
        guard toneMapAdjustmentAmount > 0 else {
            if toneMapController != nil {
                disableToneMapAdjustment()
            }
            return
        }

        guard isToneMapAdjustmentAvailable else {
            return
        }

        if toneMapController == nil {
            _ = enableToneMapAdjustment()
        }
        toneMapController?.amount = toneMapAdjustmentAmount
    }

    private func applyPreferredPortraitAdjustment() {
        guard portraitAdjustmentBlur > 0 else {
            if portraitController != nil {
                disablePortraitAdjustment()
            }
            return
        }

        guard isPortraitAdjustmentAvailable else { return }
        if portraitController == nil {
            _ = enablePortraitAdjustment()
        }
        portraitController?.blur = portraitAdjustmentBlur
    }

    private func notifyControlsDidChange() {
        let notify = { [weak self] in
            guard let self else { return }
            self.uiDelegate?.cameraControllerControlsDidChange(self)
            self.controlsDidChange?()
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    private var resolvedCaptureAspectRatio: CGFloat {
        captureAspectRatio ?? (UIScreen.main.bounds.width / UIScreen.main.bounds.height)
    }
}

// MARK: Lens Application

extension CameraController {
    /// Generates the launch data for the lens.
    /// - Parameter lens: the lens to generate launch data for
    /// - Returns: launch data.
    private func launchData(for lens: Lens) -> LensLaunchData {
        guard !lens.vendorData.isEmpty || !lensLaunchDataOverrides.isEmpty else {
            return EmptyLensLaunchData()
        }

        let launchDataBuilder = LensLaunchDataBuilder()
        for (key, val) in lens.vendorData {
            launchDataBuilder.add(string: val, key: key)
        }
        for (key, val) in lensLaunchDataOverrides {
            launchDataBuilder.add(string: val, key: key)
        }
        return launchDataBuilder.launchData ?? EmptyLensLaunchData()
    }
}

// MARK: Notifications

extension CameraController {
    /// Observes notifications relevant to the camera controller.
    private func configureNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForegroundNotification(_:)),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    /// Notifies the camera controller that the app is about to background. The app must stop processing until re-foregrounded.
    /// - Parameter notification: the NSNotification.
    @objc
    private func appWillEnterForegroundNotification(_ notification: Notification) {
        // SDK pauses/disables Lens processing in the background, so restore the complete stack.
        reapplyCurrentLenses()
    }
}

// MARK: Key-Value Observing

extension CameraController {
    /// Restores continuous autoexposure after the camera finishes a user-initiated tap to focus
    private func restoreContinuousAutoExposure(_ device: AVCaptureDevice, _ change: NSKeyValueObservedChange<Bool>) {
        guard
            let isAdjustingExposure = change.newValue,
            !isAdjustingExposure
        else {
            return
        }

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to restore continuous autoexposure")
            return
        }
    }

    /// Restores continuous autofocus after the camera finishes a user-initiated tap to focus
    private func restoreContinuousAutoFocus(_ device: AVCaptureDevice, _ change: NSKeyValueObservedChange<Bool>) {
        guard
            let isAdjustingFocus = change.newValue,
            !isAdjustingFocus
        else {
            return
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraKit] Failed to lock device for configuration when trying to restore continuous autofocus")
            return
        }
    }
}

// MARK: Lens facing preference

extension CameraController {
    /// Set camera position based on lens facing preference.
    private func changeCameraPosition(with lensFacing: LensFacingPreference) {
        var position: AVCaptureDevice.Position?
        switch lensFacing {
        case .front: position = .front
        case .back: position = .back
        default: break
        }

        if
            let position,
            position != cameraPosition
        {
            uiDelegate?.cameraControllerRequestedCameraFlip(self)
        }
    }
}

// MARK: Flash

public extension CameraController {
    /// Enumerates the different flash enabled modes.
    enum FlashMode: Int {
        case standard
        case ring
    }

    /// Enumerates the different possible flash states.
    enum FlashState: Equatable {
        case off
        case on(FlashMode)

        /// The AVCaptureDevice.FlashMode that should be used when taking photos as per the FlashState.
        public var captureDeviceFlashMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off:
                return .off
            case let .on(flashMode):
                return flashMode == .standard ? .on : .off
            }
        }

        /// The AVCaptureDevice.torchMode that should be used when recording videos as per the FlashState.
        public var captureDeviceTorchMode: AVCaptureDevice.TorchMode {
            switch self {
            case .off:
                return .off
            case let .on(flashMode):
                return flashMode == .standard ? .on : .off
            }
        }
    }

    /// Updates the flash state after a camera flip occurs.
    private func updateFlashAfterFlip() {
        switch flashState {
        case .off:
            break
        case let .on(flashMode):
            if cameraPosition == .front {
                flashState = .on(lastFrontFlashMode ?? .standard)
            } else {
                lastFrontFlashMode = flashMode
                flashState = .on(.standard)
            }
        }
    }

    /// Enables the camera flash with the appopriate flash mode as per camera position and prior user selections.
    func enableFlash() {
        if cameraPosition == .front {
            flashState = .on(lastFrontFlashMode ?? .standard)
        } else {
            flashState = .on(.standard)
        }
    }

    /// Enables or disables the front-facing screen ring light.
    func setRingLightEnabled(_ enabled: Bool) {
        guard cameraPosition == .front else {
            if isRingLightEnabled {
                flashState = .off
            }
            return
        }
        lastFrontFlashMode = .ring
        flashState = enabled ? .on(.ring) : .off
    }

    /// Sets the front-facing screen ring light intensity.
    func setRingLightIntensity(_ intensity: CGFloat) {
        ringLightIntensity = min(max(intensity, 0), 1)
        notifyControlsDidChange()
    }

    /// Sets the front-facing screen ring light color.
    func setRingLightColor(_ color: UIColor) {
        ringLightColor = color
        notifyControlsDidChange()
    }

    /// Disables the camera flash.
    func disableFlash() {
        switch flashState {
        case .off:
            break
        case let .on(flashMode):
            if cameraPosition == .front {
                lastFrontFlashMode = flashMode
            }
            flashState = .off
        }
    }

    /// Updates the UI as necessary upon changes to `flashState`.
    /// Called in the `didSet` property observer of `flashState`.
    private func handleFlashStateChange(oldValue: FlashState) {
        guard flashState != oldValue else { return }

        restoreBrightnessIfNecessary()
        switch flashState {
        case .off:
            uiDelegate?.cameraControllerRequestedRingLightHide(self)
            uiDelegate?.cameraControllerRequestedFlashControlHide(self)
        case let .on(flashMode):
            switch flashMode {
            case .standard:
                uiDelegate?.cameraControllerRequestedRingLightHide(self)
            case .ring:
                uiDelegate?.cameraControllerRequestedRingLightShow(self)
                increaseBrightnessIfNecessary()
            }
        }
        notifyControlsDidChange()
    }

    /// Restores brightness to what it was before the ring light was enabled.
    func restoreBrightnessIfNecessary() {
        if let brightnessToRestore {
            UIScreen.main.brightness = brightnessToRestore
            if flashState != .on(.ring) {
                self.brightnessToRestore = nil
            }
        }
    }

    /// Increases brightness to max if the ring light is enabled.
    func increaseBrightnessIfNecessary() {
        if flashState == .on(.ring) {
            brightnessToRestore = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
    }
}
