import UIKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

private final class StaticCarouselDataSource: CarouselViewDataSource {
    let items: [CarouselItem]

    init(items: [CarouselItem]) {
        self.items = items
    }

    func itemsForCarouselView(_ view: CarouselView) -> [CarouselItem] {
        items
    }
}

final class CarouselContextMenuTests: XCTestCase {
    func testUnmanagedItemDoesNotCreateContextMenu() {
        let item = CarouselItem(lensId: "cloud-lens", groupId: "cloud")
        let dataSource = StaticCarouselDataSource(items: [item])
        let carousel = CarouselView()
        carousel.dataSource = dataSource

        let configuration = carousel.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            contextMenuConfigurationForItemAt: IndexPath(item: 0, section: 0),
            point: .zero
        )

        XCTAssertNil(configuration)
    }

    func testManagedItemCreatesContextMenuLazily() {
        var requestCount = 0
        let item = CarouselItem(
            lensId: "localized-lens",
            groupId: "vibecheck.localized-lenses",
            contextMenuProvider: {
                requestCount += 1
                return UIMenu(title: "Localized Lens", children: [])
            }
        )
        let dataSource = StaticCarouselDataSource(items: [item])
        let carousel = CarouselView()
        carousel.dataSource = dataSource

        XCTAssertEqual(requestCount, 0)
        let configuration = carousel.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            contextMenuConfigurationForItemAt: IndexPath(item: 0, section: 0),
            point: .zero
        )

        XCTAssertNotNil(configuration)
        XCTAssertEqual(requestCount, 1)
    }
}
