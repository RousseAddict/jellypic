import UIKit
import ImageIO

final class ImageLoader {

    static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024,
                                          diskCapacity: 200 * 1024 * 1024,
                                          diskPath: "jellypic.images")
        return configuration
    }

    private let client: JellyfinAPI
    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private let decodeQueue = DispatchQueue(label: "jellypic.image.decode", qos: .userInitiated)

    init(client: JellyfinAPI,
         configuration: URLSessionConfiguration = ImageLoader.defaultConfiguration()) {
        self.client = client
        self.session = URLSession(configuration: configuration)
        memory.totalCostLimit = 24 * 1024 * 1024

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dropMemoryCache),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func cached(itemId: String, tag: String?, pixels: Int) -> UIImage? {
        return memory.object(forKey: key(itemId: itemId, tag: tag, pixels: pixels) as NSString)
    }

    func load(itemId: String,
              tag: String?,
              pixels: Int,
              completion: @escaping (UIImage?) -> Void) -> URLSessionTask? {
        let cacheKey = key(itemId: itemId, tag: tag, pixels: pixels)
        if let hit = memory.object(forKey: cacheKey as NSString) {
            completion(hit)
            return nil
        }
        guard let request = client.imageRequest(itemId: itemId, tag: tag, fillPixels: pixels) else {
            completion(nil)
            return nil
        }

        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.decodeQueue.async {
                let image = ImageLoader.decode(data, pixels: pixels)
                if let image = image {
                    self.memory.setObject(image, forKey: cacheKey as NSString, cost: ImageLoader.cost(of: image))
                }
                DispatchQueue.main.async { completion(image) }
            }
        }
        task.resume()
        return task
    }

    func clearCaches() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    @objc private func dropMemoryCache() {
        memory.removeAllObjects()
    }

    private func key(itemId: String, tag: String?, pixels: Int) -> String {
        return "\(itemId)|\(tag ?? "-")|\(pixels)"
    }

    private static func decode(_ data: Data, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
