//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import Photos
import UIKit

/// Preview view controller for showing captured photos and images
public class ImagePreviewViewController: PreviewViewController {
    // MARK: Properties

    /// UIImage to display
    public let image: UIImage

    fileprivate lazy var imageView: UIImageView = {
        let view = UIImageView(image: image)
        view.accessibilityIdentifier = PreviewElements.imageView.id
        view.contentMode = .scaleAspectFill
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    // MARK: Init

    /// Designated init to pass in required deps
    /// - Parameter image: UIImage to display
    public init(image: UIImage) {
        self.image = image
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

    // MARK: Setup

    private func setup() {
        view.insertSubview(imageView, at: 0)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: Action Overrides

    override public func openSnapchatPressed(_ sender: UIButton) {
        snapchatDelegate?.cameraKitViewController(self, openSnapchat: .photo(image))
    }

    override public func sharePreviewPressed(_ sender: UIButton) {
        let viewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        viewController.popoverPresentationController?.sourceView = sender
        present(viewController, animated: true, completion: nil)
    }

    override public func savePreviewPressed(_ sender: UIButton) {
        VibeCheckPhotoLibrarySaver.save(image: image) { saved, error in
            var title: String
            var message: String
            if saved {
                title = "Save Success"
                message = "Successfully saved photo to Vibe Check"
            } else {
                title = "Save Failure"
                message = "Failed to save photo to library"
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
}
