//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// This is the carousel item view model which represents a specific lens icon
public class CarouselItem: Identifiable, Equatable {
    /// id for carousel item
    public let id: String

    /// lens id
    public let lensId: String

    /// group id lens belongs to
    public let groupId: String

    /// image url for lens icon
    public let imageUrl: URL?

    /// downloaded image for lens icon
    public var image: UIImage?

    /// Provides a native context menu when the item is long-pressed.
    public let contextMenuProvider: (() -> UIMenu?)?

    /// Designated init for a carousel item
    /// - Parameters:
    ///   - lensId: lens id
    ///   - groupId: group id that lens belongs to
    ///   - imageUrl: optional image url of lens icon
    ///   - image: optional loaded UIImage of icon
    public init(
        lensId: String,
        groupId: String,
        imageUrl: URL? = nil,
        image: UIImage? = nil,
        contextMenuProvider: (() -> UIMenu?)? = nil
    ) {
        self.id = lensId + groupId
        self.lensId = lensId
        self.groupId = groupId
        self.imageUrl = imageUrl
        self.image = image
        self.contextMenuProvider = contextMenuProvider
    }

    public static func == (lhs: CarouselItem, rhs: CarouselItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Concrete class for an empty item (clear camera button)
public class EmptyItem: CarouselItem {
    public init() {
        super.init(
            lensId: "empty",
            groupId: "empty",
            imageUrl: nil,
            image: UIImage(named: "ck_lens_empty", in: BundleHelper.resourcesBundle, compatibleWith: nil)
        )
    }
}
