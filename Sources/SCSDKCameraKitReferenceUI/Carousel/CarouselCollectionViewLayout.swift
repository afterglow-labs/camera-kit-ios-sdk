//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// Delegate for custom carousel collection view layout
public protocol CarouselCollectionViewLayoutDelegate: AnyObject {
    /// This method is called when user stops scrolling and layout will target the correct lens to land at
    /// - Parameters:
    ///   - layout: carousel collection view layout instance
    ///   - index: index of item that it will land at
    func carouselLayout(_ layout: CarouselCollectionViewLayout, willTargetIndex index: Int)
}

/// Data source for custom carousel collection view layout
public protocol CarouselCollectionViewLayoutDataSource: AnyObject {
    /// Method to provide any sort of transform that should be applied to the carousel cell
    /// - Parameters:
    ///   - layout: carousel collection view layout instance
    ///   - indexPath: index path of cell
    func carouselLayout(_ layout: CarouselCollectionViewLayout, transformForItemAt indexPath: IndexPath)
        -> CGAffineTransform
}

/// Custom collection view layout for carousel collection view
public class CarouselCollectionViewLayout: UICollectionViewFlowLayout {
    /// Weak ref to carousel layout delegate
    public weak var delegate: CarouselCollectionViewLayoutDelegate?

    /// Weak ref to carousel layout data source
    public weak var dataSource: CarouselCollectionViewLayoutDataSource?

    /// Override flow layout target content offset to land at a specific item (for the paging effect)
    /// - Parameters:
    ///   - proposedContentOffset: proposed content offset of flow layout to land at
    ///   - velocity: scrolling velocity of collection view
    override public func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView else { return proposedContentOffset }

        let isVertical = scrollDirection == .vertical
        let proposedOffset = isVertical ? proposedContentOffset.y : proposedContentOffset.x
        let inset = isVertical ? collectionView.contentInset.top : collectionView.contentInset.left
        let itemExtent = isVertical ? itemSize.height : itemSize.width
        let spacing = minimumLineSpacing
        let offset = proposedOffset + inset
        let index = offset / (itemExtent + spacing)
        let pageIndex = index.rounded()

        delegate?.carouselLayout(self, willTargetIndex: Int(pageIndex))

        let newTarget = pageIndex * (itemExtent + spacing) - inset
        return isVertical
            ? CGPoint(x: proposedContentOffset.x, y: newTarget)
            : CGPoint(x: newTarget, y: proposedContentOffset.y)
    }

    override public func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let list = super.layoutAttributesForElements(in: rect) else { return nil }
        return list.map { attributes in
            guard let ret = attributes.copy() as? UICollectionViewLayoutAttributes else {
                return attributes
            }

            if let transform = dataSource?.carouselLayout(self, transformForItemAt: ret.indexPath) {
                ret.transform = transform
            }

            return ret
        }
    }
}
