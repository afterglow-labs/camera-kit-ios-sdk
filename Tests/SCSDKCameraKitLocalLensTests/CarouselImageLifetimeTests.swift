import UIKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

private final class ImmediateCarouselImageLoader: CarouselImageLoader {
    let image: UIImage
    private(set) var requestedURLs: [URL] = []
    private(set) var cancelledURLs: [URL] = []

    init(image: UIImage) {
        self.image = image
    }

    func loadImage(url: URL, completion: ((UIImage?, Error?) -> Void)?) {
        requestedURLs.append(url)
        completion?(image, nil)
    }

    func loadImage(
        url: URL,
        cachePolicy: URLRequest.CachePolicy,
        queue: DispatchQueue,
        completion: ((UIImage?, Error?) -> Void)?
    ) {
        requestedURLs.append(url)
        queue.async { [image] in
            completion?(image, nil)
        }
    }

    func cancelImageLoad(from url: URL) {
        cancelledURLs.append(url)
    }
}

private final class ImageLifetimeCarouselDataSource: CarouselViewDataSource {
    let item: CarouselItem

    init(item: CarouselItem) {
        self.item = item
    }

    func itemsForCarouselView(_ view: CarouselView) -> [CarouselItem] {
        [item]
    }
}

final class CarouselImageLifetimeTests: XCTestCase {
    func testURLBackedImageIsNotRetainedByCarouselItem() {
        let url = URL(fileURLWithPath: "/tmp/localized-lens.webp")
        let item = CarouselItem(lensId: "lens", groupId: "localized", imageUrl: url)
        let source = ImageLifetimeCarouselDataSource(item: item)
        let loader = ImmediateCarouselImageLoader(image: solidImage(size: CGSize(width: 64, height: 64)))
        let carousel = CarouselView(imageLoader: loader)
        carousel.dataSource = source

        carousel.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            willDisplay: UICollectionViewCell(),
            forItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertEqual(loader.requestedURLs, [url])
        XCTAssertNil(item.image, "URL-backed thumbnails must not accumulate on every carousel item")
    }

    func testLocalThumbnailIsDownsampledBeforeCaching() throws {
        let sourceImage = solidImage(size: CGSize(width: 360, height: 640))
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try sourceImage.pngData()?.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let loader = DefaultCarouselImageLoader(maximumPixelDimension: 96)
        let loaded = expectation(description: "thumbnail loaded")
        loader.loadImage(url: sourceURL) { image, error in
            XCTAssertNil(error)
            let dimensions = image?.cgImage.map { CGSize(width: $0.width, height: $0.height) }
            XCTAssertLessThanOrEqual(max(dimensions?.width ?? .greatestFiniteMagnitude, dimensions?.height ?? .greatestFiniteMagnitude), 96)
            loaded.fulfill()
        }

        wait(for: [loaded], timeout: 2)
    }

    func testOffscreenCellReleasesItsThumbnailImmediately() {
        let url = URL(fileURLWithPath: "/tmp/localized-lens.webp")
        let item = CarouselItem(lensId: "lens", groupId: "localized", imageUrl: url)
        let source = ImageLifetimeCarouselDataSource(item: item)
        let loader = ImmediateCarouselImageLoader(image: solidImage(size: CGSize(width: 64, height: 64)))
        let carousel = CarouselView(imageLoader: loader)
        let cell = CarouselCollectionViewCell()
        cell.imageView.image = loader.image
        cell.activityIndicatorView.startAnimating()
        carousel.dataSource = source

        carousel.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            didEndDisplaying: cell,
            forItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertNil(cell.imageView.image)
        XCTAssertFalse(cell.activityIndicatorView.isAnimating)
        XCTAssertEqual(loader.cancelledURLs, [url])
    }

    func testCancellingThumbnailLoadEvictsDecodedImage() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let loader = DefaultCarouselImageLoader(maximumPixelDimension: 96)
        try solidImage(size: CGSize(width: 200, height: 100), color: .magenta).pngData()?.write(to: sourceURL)
        let landscapeThumbnail = try loadImage(at: sourceURL, with: loader)
        XCTAssertEqual(landscapeThumbnail.cgImage?.width, 96)
        XCTAssertEqual(landscapeThumbnail.cgImage?.height, 48)

        loader.cancelImageLoad(from: sourceURL)
        try solidImage(size: CGSize(width: 100, height: 200), color: .cyan).pngData()?.write(to: sourceURL)
        let portraitThumbnail = try loadImage(at: sourceURL, with: loader)

        XCTAssertEqual(portraitThumbnail.cgImage?.width, 48)
        XCTAssertEqual(portraitThumbnail.cgImage?.height, 96)
    }

    func testVerticalCarouselCapsViewportAtFiveLensSlots() {
        let carousel = CarouselView()
        carousel.frame = CGRect(x: 0, y: 0, width: 62, height: 700)
        carousel.orientation = .vertical
        carousel.layoutIfNeeded()

        let collectionView = carousel.subviews.compactMap { $0 as? UICollectionView }.first
        XCTAssertEqual(collectionView?.bounds.height ?? 0, 342, accuracy: 0.5)
    }

    func testVerticalCarouselCanCapViewportAtFourLensSlots() {
        let carousel = CarouselView()
        carousel.frame = CGRect(x: 0, y: 0, width: 62, height: 700)
        carousel.orientation = .vertical
        carousel.maximumVisibleItemCount = 4
        carousel.layoutIfNeeded()

        let collectionView = carousel.subviews.compactMap { $0 as? UICollectionView }.first
        XCTAssertEqual(collectionView?.bounds.height ?? 0, 272, accuracy: 0.5)
    }

    private func loadImage(at url: URL, with loader: DefaultCarouselImageLoader) throws -> UIImage {
        let loaded = expectation(description: "thumbnail loaded")
        var result: Result<UIImage, Error>?
        loader.loadImage(url: url) { image, error in
            if let image {
                result = .success(image)
            } else {
                result = .failure(error ?? CocoaError(.fileReadCorruptFile))
            }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)
        return try XCTUnwrap(result).get()
    }

    private func solidImage(size: CGSize, color: UIColor = .magenta) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
