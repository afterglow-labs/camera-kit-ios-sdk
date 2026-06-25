//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import AVKit
import Photos
import UIKit

/// Preview view controller for showing recorded video previews
public class VideoPreviewViewController: PreviewViewController {
    // MARK: Properties

    /// URL which contains video file
    public let videoUrl: URL

    /// AVPlayerItem for video file url
    lazy var playerItem = AVPlayerItem(url: videoUrl)

    /// AVQueuePlayer for the video
    lazy var videoPlayer = AVQueuePlayer(playerItem: playerItem)

    // MARK: Views

    /// AVPlayerViewController for the video
    lazy var playerController: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.player = videoPlayer
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        return controller
    }()

    /// Player looper to loop video automatically
    lazy var playerLooper = AVPlayerLooper(player: videoPlayer, templateItem: playerItem)

    // MARK: Init

    /// Init with url to video file
    /// - Parameter videoUrl: url to video file
    public init(videoUrl: URL) {
        self.videoUrl = videoUrl
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        setupVideoPlayer()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackgroundNotification(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForegroundNotification(_:)),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    // MARK: Action Overrides

    override public func openSnapchatPressed(_ sender: UIButton) {
        snapchatDelegate?.cameraKitViewController(self, openSnapchat: .video(videoUrl))
    }

    override public func sharePreviewPressed(_ sender: UIButton) {
        let viewController = UIActivityViewController(activityItems: [videoUrl], applicationActivities: nil)
        viewController.popoverPresentationController?.sourceView = sender
        viewController.completionWithItemsHandler = { [weak self] _, _, _, _ in
            guard
                let strongSelf = self,
                strongSelf.videoPlayer.rate == 0 || strongSelf.videoPlayer.error != nil
            else {
                return
            }

            strongSelf.videoPlayer.play()
        }
        present(viewController, animated: true, completion: nil)
    }

    override public func savePreviewPressed(_ sender: UIButton) {
        VibeCheckPhotoLibrarySaver.saveVideo(at: videoUrl) { saved, error in
            var title: String
            var message: String
            if saved {
                title = "Save Success"
                message = "Successfully saved video to Vibe Check"
            } else {
                title = "Save Failure"
                message = "Failed to save video to library"
                print("failed to save video with error: \(error?.localizedDescription ?? "no error")")
            }

            DispatchQueue.main.async {
                let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
                let action = UIAlertAction(title: "OK", style: .default, handler: nil)
                alertController.addAction(action)
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }

    // MARK: App Lifecyle Notifications

    @objc
    private func appDidEnterBackgroundNotification(_ notification: Notification) {
        videoPlayer.pause()
    }

    @objc
    private func appWillEnterForegroundNotification(_ notification: Notification) {
        videoPlayer.play()
    }
}

// MARK: Video Player

extension VideoPreviewViewController {
    private func setupVideoPlayer() {
        addChild(playerController)
        view.insertSubview(playerController.view, at: 0)
        playerController.didMove(toParent: self)
        playerController.view.accessibilityIdentifier = PreviewElements.playerControllerView.id

        NSLayoutConstraint.activate([
            playerController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        guard playerLooper.error == nil else { return }
        videoPlayer.play()
    }
}
