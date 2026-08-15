//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import ImageIO
import UIKit

/// Protocol used to load an image from url
public protocol CarouselImageLoader: AnyObject {
    /// Load image from url
    /// - Parameters:
    ///   - url: image url
    ///   - completion: callback with image on success or error on failure
    func loadImage(url: URL, completion: ((_ image: UIImage?, _ error: Error?) -> Void)?)

    /// Load image from url
    /// - Parameters:
    ///   - url: image url
    ///   - cachePolicy: cache policy for the requested image data
    ///   - queue: queue to call completion on
    ///   - completion: callback with image on success or error on failure
    func loadImage(
        url: URL,
        cachePolicy: URLRequest.CachePolicy,
        queue: DispatchQueue,
        completion: ((UIImage?, Error?) -> Void)?
    )

    /// Cancels image loading for a given url
    func cancelImageLoad(from url: URL)
}

/// Default image loader class which uses a URLSession to load images
public class DefaultCarouselImageLoader: CarouselImageLoader {
    public let urlSession: URLSession
    fileprivate var tasks: [URL: URLSessionDataTask] = [:]
    fileprivate var fileTaskTokens: [URL: UUID] = [:]
    fileprivate let taskQueue = DispatchQueue(label: "com.snap.camerakit.referenceui.imageloader")
    fileprivate let fileQueue = DispatchQueue(
        label: "com.snap.camerakit.referenceui.imageloader.files",
        qos: .userInitiated
    )
    private let imageCache = NSCache<NSURL, UIImage>()
    private let maximumPixelDimension: CGFloat
    private var memoryWarningObserver: NSObjectProtocol?

    public init(
        urlSession: URLSession = .shared,
        maximumPixelDimension: CGFloat = 192,
        cacheCountLimit: Int = 96,
        cacheCostLimit: Int = 24 * 1_024 * 1_024
    ) {
        self.urlSession = urlSession
        self.maximumPixelDimension = max(1, maximumPixelDimension)
        imageCache.countLimit = max(1, cacheCountLimit)
        imageCache.totalCostLimit = max(1, cacheCostLimit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak imageCache] _ in
            imageCache?.removeAllObjects()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        taskQueue.sync {
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
            fileTaskTokens.removeAll()
        }
    }

    public func loadImage(url: URL, completion: ((UIImage?, Error?) -> Void)?) {
        loadImage(url: url, queue: .main, completion: completion)
    }

    public func loadImage(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        queue: DispatchQueue,
        completion: ((UIImage?, Error?) -> Void)?
    ) {
        if let cachedImage = imageCache.object(forKey: url as NSURL) {
            queue.async {
                completion?(cachedImage, nil)
            }
            return
        }

        if url.isFileURL {
            let token = UUID()
            taskQueue.sync {
                fileTaskTokens[url] = token
            }
            fileQueue.async { [weak self] in
                guard let self, self.isFileTaskActive(token, for: url) else { return }
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard self.isFileTaskActive(token, for: url) else { return }
                    guard let image = self.thumbnail(from: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    guard self.finishFileTask(token, for: url) else { return }
                    self.cache(image, for: url)
                    queue.async {
                        completion?(image, nil)
                    }
                } catch {
                    guard self.finishFileTask(token, for: url) else { return }
                    queue.async {
                        completion?(nil, error)
                    }
                }
            }
            return
        }

        let request = URLRequest(url: url, cachePolicy: cachePolicy)
        let task = urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            self.removeTask(url: url)
            guard
                let data,
                let image = self.thumbnail(from: data)
            else {
                queue.async {
                    completion?(nil, error)
                }
                return
            }
            self.cache(image, for: url)
            queue.async {
                completion?(image, nil)
            }
        }

        addTask(task, for: url)
        task.resume()
    }

    public func cancelImageLoad(from url: URL) {
        taskQueue.sync {
            self.tasks[url]?.cancel()
            self.tasks[url] = nil
            self.fileTaskTokens[url] = nil
        }
        imageCache.removeObject(forKey: url as NSURL)
    }

    fileprivate func addTask(_ task: URLSessionDataTask, for url: URL) {
        taskQueue.sync {
            self.tasks[url]?.cancel()
            self.tasks[url] = task
        }
    }

    fileprivate func removeTask(url: URL) {
        taskQueue.sync {
            self.tasks[url] = nil
        }
    }

    private func isFileTaskActive(_ token: UUID, for url: URL) -> Bool {
        taskQueue.sync {
            fileTaskTokens[url] == token
        }
    }

    private func finishFileTask(_ token: UUID, for url: URL) -> Bool {
        taskQueue.sync {
            guard fileTaskTokens[url] == token else { return false }
            fileTaskTokens[url] = nil
            return true
        }
    }

    private func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelDimension.rounded(.up)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image, scale: UIScreen.main.scale, orientation: .up)
    }

    private func cache(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        imageCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
