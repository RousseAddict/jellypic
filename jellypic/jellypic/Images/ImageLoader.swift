import UIKit
import ImageIO

enum ImageLoadResult {
    case image(UIImage)
    case deferred
    case failed(String)
    case expired
}

final class ImageLoader {

    static let unreachableMessage = "The server is unreachable."
    static let missingMessage = "This photo is no longer on the server."
    static let genericMessage = "This photo could not be loaded."
    static let expiredMessage = "Your session has expired."

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
    private let fullSize = NSCache<NSString, UIImage>()
    private let decodeQueue = DispatchQueue(label: "jellypic.image.decode", qos: .userInitiated)

    var isSuspended = false
    var onUnauthorized: (() -> Void)?

    init(client: JellyfinAPI,
         configuration: URLSessionConfiguration = ImageLoader.defaultConfiguration()) {
        self.client = client
        self.session = URLSession(configuration: configuration)
        memory.totalCostLimit = 24 * 1024 * 1024
        fullSize.countLimit = 3

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
              completion: @escaping (ImageLoadResult) -> Void) -> URLSessionTask? {
        let cacheKey = key(itemId: itemId, tag: tag, pixels: pixels)
        if let hit = memory.object(forKey: cacheKey as NSString) {
            completion(.image(hit))
            return nil
        }
        guard !isSuspended else {
            completion(.deferred)
            return nil
        }
        guard let request = client.imageRequest(itemId: itemId, tag: tag, fillPixels: pixels) else {
            completion(.failed(ImageLoader.genericMessage))
            return nil
        }
        let isSignedOut = client.credentials == nil

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(.deferred) }
                return
            }
            self.reportIfUnauthorized(response)
            switch ImageLoader.payload(data: data,
                                       response: response,
                                       error: error,
                                       isSignedOut: isSignedOut) {
            case .outcome(let outcome):
                DispatchQueue.main.async { completion(outcome) }
            case .body(let body):
                self.decodeQueue.async {
                    guard let image = ImageLoader.decode(body, pixels: pixels) else {
                        DispatchQueue.main.async { completion(.failed(ImageLoader.genericMessage)) }
                        return
                    }
                    self.memory.setObject(image,
                                          forKey: cacheKey as NSString,
                                          cost: ImageLoader.cost(of: image))
                    DispatchQueue.main.async { completion(.image(image)) }
                }
            }
        }
        task.resume()
        return task
    }

    func loadFull(itemId: String,
                  tag: String?,
                  maxPixels: Int,
                  completion: @escaping (ImageLoadResult) -> Void) -> URLSessionTask? {
        let cacheKey = key(itemId: itemId, tag: tag, pixels: maxPixels)
        if let hit = fullSize.object(forKey: cacheKey as NSString) {
            completion(.image(hit))
            return nil
        }
        guard let request = client.fullImageRequest(itemId: itemId, tag: tag, maxPixels: maxPixels) else {
            completion(.failed(ImageLoader.genericMessage))
            return nil
        }
        let isSignedOut = client.credentials == nil

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(.deferred) }
                return
            }
            self.reportIfUnauthorized(response)
            switch ImageLoader.payload(data: data,
                                       response: response,
                                       error: error,
                                       isSignedOut: isSignedOut) {
            case .outcome(let outcome):
                DispatchQueue.main.async { completion(outcome) }
            case .body(let body):
                self.decodeQueue.async {
                    guard let image = ImageLoader.decode(body, pixels: maxPixels) else {
                        DispatchQueue.main.async { completion(.failed(ImageLoader.genericMessage)) }
                        return
                    }
                    self.fullSize.setObject(image, forKey: cacheKey as NSString)
                    DispatchQueue.main.async { completion(.image(image)) }
                }
            }
        }
        task.resume()
        return task
    }

    func releaseFullSize() {
        fullSize.removeAllObjects()
    }

    func diskUsage() -> Int64 {
        return Int64(session.configuration.urlCache?.currentDiskUsage ?? 0)
    }

    func clearCaches() {
        memory.removeAllObjects()
        fullSize.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    private func reportIfUnauthorized(_ response: URLResponse?) {
        guard let http = response as? HTTPURLResponse,
              HTTPStatus.rejectsToken(http.statusCode) else { return }
        DispatchQueue.main.async { self.onUnauthorized?() }
    }

    @objc private func dropMemoryCache() {
        memory.removeAllObjects()
        fullSize.removeAllObjects()
    }

    private func key(itemId: String, tag: String?, pixels: Int) -> String {
        return "\(itemId)|\(tag ?? "-")|\(pixels)"
    }

    private enum Payload {
        case body(Data)
        case outcome(ImageLoadResult)
    }

    private static func payload(data: Data?,
                                response: URLResponse?,
                                error: Error?,
                                isSignedOut: Bool) -> Payload {
        if let error = error {
            guard (error as? URLError)?.code != .cancelled else { return .outcome(.deferred) }
            guard !isSignedOut else { return .outcome(.expired) }
            return .outcome(.failed(error is URLError ? unreachableMessage : genericMessage))
        }
        if let http = response as? HTTPURLResponse, HTTPStatus.rejectsToken(http.statusCode) {
            return .outcome(.expired)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return .outcome(.failed(http.statusCode == 404 ? missingMessage : genericMessage))
        }
        guard let data = data, !data.isEmpty else { return .outcome(.failed(genericMessage)) }
        return .body(data)
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
