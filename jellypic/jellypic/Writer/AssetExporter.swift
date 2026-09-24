import CommonCrypto
import Foundation
import Photos
import UIKit

struct AssetExport {
    let fileURL: URL
    let sha256: String
    let fileName: String
    let capturedAt: Date?
}

enum AssetExportFailure: Error {
    case denied
    case noAsset
    case noResource
    case notLocal
    case write
}

final class AssetExporter {

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Uploads", isDirectory: true)
    }

    static func stagedName(for identifier: String) -> String {
        var digest = SHA256Digest()
        digest.update(Data(identifier.utf8))
        return digest.finalize()
    }

    func sweep(keeping names: Set<String>) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil,
                                                             options: []) else { return }
        for entry in entries where !names.contains(entry.lastPathComponent) {
            try? manager.removeItem(at: entry)
        }
    }

    func discard(_ export: AssetExport) {
        try? FileManager.default.removeItem(at: export.fileURL)
    }

    func discardStaged(for identifier: String) {
        try? FileManager.default.removeItem(at: directory
            .appendingPathComponent(AssetExporter.stagedName(for: identifier)))
    }

    func exportMostRecent(completion: @escaping (Result<AssetExport, AssetExportFailure>) -> Void) {
        requestAuthorization { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                completion(.failure(.denied))
                return
            }
            guard let asset = AssetExporter.mostRecentAsset() else {
                completion(.failure(.noAsset))
                return
            }
            self.export(asset, identifier: asset.localIdentifier, completion: completion)
        }
    }

    func export(_ asset: PHAsset,
                identifier: String,
                completion: @escaping (Result<AssetExport, AssetExportFailure>) -> Void) {
        guard let resource = AssetExporter.resource(for: asset) else {
            DispatchQueue.main.async { completion(.failure(.noResource)) }
            return
        }
        guard let fileURL = makeFileURL(for: identifier),
              let stream = OutputStream(url: fileURL, append: false) else {
            DispatchQueue.main.async { completion(.failure(.write)) }
            return
        }

        stream.open()

        var digest = SHA256Digest()
        var received = 0
        var wroteEverything = true
        var isExpired = false
        var isDelivered = false
        var backgroundTask = UIBackgroundTaskIdentifier.invalid

        let deliver: (Result<AssetExport, AssetExportFailure>) -> Void = { outcome in
            guard !isDelivered else { return }
            isDelivered = true
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            completion(outcome)
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "JellypicExport") {
            isExpired = true
            try? FileManager.default.removeItem(at: fileURL)
            deliver(.failure(.write))
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
            guard wroteEverything, !isExpired else { return }
            digest.update(data)
            received += data.count
            wroteEverything = AssetExporter.write(data, to: stream)
        }, completionHandler: { error in
            stream.close()

            let sha256 = digest.finalize()
            let outcome: Result<AssetExport, AssetExportFailure>

            if error != nil {
                outcome = .failure(.notLocal)
            } else if isExpired || !wroteEverything || received == 0 {
                outcome = .failure(.write)
            } else {
                outcome = .success(AssetExport(fileURL: fileURL,
                                               sha256: sha256,
                                               fileName: resource.originalFilename,
                                               capturedAt: asset.creationDate))
            }

            if case .failure = outcome {
                try? FileManager.default.removeItem(at: fileURL)
            }

            DispatchQueue.main.async { deliver(outcome) }
        })
    }

    // LEGACY(ios12): no .limited branch, PHAuthorizationStatus gains it at iOS 14
    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    private func makeFileURL(for identifier: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            return nil
        }
        return directory.appendingPathComponent(AssetExporter.stagedName(for: identifier))
    }

    private static func mostRecentAsset() -> PHAsset? {
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                  subtype: .smartAlbumUserLibrary,
                                                                  options: nil)
        guard let library = collections.firstObject else { return nil }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: library, options: options).firstObject
    }

    private static func resource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = asset.mediaType == .video
            ? [.fullSizeVideo, .video]
            : [.fullSizePhoto, .photo]
        for type in preferred {
            if let match = resources.first(where: { $0.type == type }) {
                return match
            }
        }
        return resources.first
    }

    private static func write(_ data: Data, to stream: OutputStream) -> Bool {
        var complete = true
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var pointer = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = stream.write(pointer, maxLength: remaining)
                guard written > 0 else {
                    complete = false
                    return
                }
                pointer += written
                remaining -= written
            }
        }
        return complete
    }
}

private struct SHA256Digest {

    private var context = CC_SHA256_CTX()

    init() {
        CC_SHA256_Init(&context)
    }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            CC_SHA256_Update(&context, base, CC_LONG(raw.count))
        }
    }

    mutating func finalize() -> String {
        var bytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&bytes, &context)
        return bytes.reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}
