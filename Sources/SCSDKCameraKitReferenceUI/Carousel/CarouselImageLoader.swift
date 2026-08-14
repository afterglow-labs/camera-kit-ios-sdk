//  Copyright Snap Inc. All rights reserved.
//  CameraKit

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
    fileprivate let taskQueue = DispatchQueue(label: "com.snap.camerakit.referenceui.imageloader")
    fileprivate let fileQueue = DispatchQueue(
        label: "com.snap.camerakit.referenceui.imageloader.files",
        qos: .userInitiated
    )

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
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
        if url.isFileURL {
            fileQueue.async {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard let image = UIImage(data: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    queue.async {
                        completion?(image, nil)
                    }
                } catch {
                    queue.async {
                        completion?(nil, error)
                    }
                }
            }
            return
        }

        let request = URLRequest(url: url, cachePolicy: cachePolicy)
        let task = urlSession.dataTask(with: request) { [weak self] data, _, error in
            self?.removeTask(url: url)
            guard
                let data,
                let image = UIImage(data: data)
            else {
                queue.async {
                    completion?(nil, error)
                }
                return
            }
            queue.async {
                completion?(image, nil)
            }
        }

        addTask(task, for: url)
        task.resume()
    }

    public func cancelImageLoad(from url: URL) {
        taskQueue.async {
            self.tasks[url]?.cancel()
            self.tasks[url] = nil
        }
    }

    fileprivate func addTask(_ task: URLSessionDataTask, for url: URL) {
        taskQueue.async {
            self.tasks[url] = task
        }
    }

    fileprivate func removeTask(url: URL) {
        taskQueue.async {
            self.tasks[url] = nil
        }
    }
}
