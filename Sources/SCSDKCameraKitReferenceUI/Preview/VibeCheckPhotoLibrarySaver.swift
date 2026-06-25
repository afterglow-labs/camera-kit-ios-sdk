//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import Photos
import UIKit

enum VibeCheckPhotoLibrarySaver {
    static let albumTitle = "Vibe Check"

    static func save(image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            addCreatedAssetToAlbum(assetRequest.placeholderForCreatedAsset)
        }, completionHandler: completion)
    }

    static func saveVideo(at url: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            addCreatedAssetToAlbum(assetRequest?.placeholderForCreatedAsset)
        }, completionHandler: completion)
    }

    private static func addCreatedAssetToAlbum(_ placeholder: PHObjectPlaceholder?) {
        guard let placeholder else { return }

        let albumRequest: PHAssetCollectionChangeRequest
        if let existingAlbum = fetchAlbum() {
            guard let request = PHAssetCollectionChangeRequest(for: existingAlbum) else { return }
            albumRequest = request
        } else {
            albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
        }

        albumRequest.addAssets([placeholder] as NSArray)
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        ).firstObject
    }
}
