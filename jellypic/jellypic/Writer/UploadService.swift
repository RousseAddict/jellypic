import Foundation
import Photos
import UIKit

enum BackupMode: Int {
    case off = 0
    case manual = 1
    case automatic = 2
}

enum BackupAvailability {
    case unknown
    case notInstalled
    case incompatible
    case blocked(String)
    case ready(UploadTarget)

    var allowsChanges: Bool {
        switch self {
        case .notInstalled, .incompatible:
            return false
        case .unknown, .blocked, .ready:
            return true
        }
    }
}

enum BackupUploadError: Error {
    case notReady
    case permissionDenied
    case photoUnavailable
    case unauthorized
    case waitingForWiFi
    case refused(String)

    var text: String {
        switch self {
        case .notReady:
            return "Your server is not ready to take photos yet."
        case .permissionDenied:
            return "Jellypic cannot read your photos. Allow access in the Settings app."
        case .photoUnavailable:
            return "No photo on this device could be read."
        case .unauthorized:
            return "Your session expired. Sign in again to continue."
        case .waitingForWiFi:
            return "Waiting for Wi-Fi to send your photos."
        case .refused(let reason):
            return reason + "."
        }
    }

    static func from(_ failure: AssetExportFailure) -> BackupUploadError {
        switch failure {
        case .denied:
            return .permissionDenied
        case .noAsset, .noResource, .notLocal:
            return .photoUnavailable
        case .write:
            return .refused("Could not stage the photo on this device")
        }
    }

    static func from(_ failure: UploadFailure) -> BackupUploadError {
        switch failure {
        case .unauthorized:
            return .unauthorized
        case .offline:
            return .waitingForWiFi
        case .transient:
            return .refused("Your server did not answer")
        case .stopQueue(let code), .rejected(let code):
            return .refused(refusalText(code))
        }
    }

    static func refusalText(_ reason: String?) -> String {
        switch reason {
        case "READ_ONLY_MOUNT"?:
            return "Your server's photo folder is read-only"
        case "PERMISSION_DENIED"?:
            return "Your server is not allowed to write to the photo folder"
        case "PATH_MISSING"?:
            return "The photo folder is missing on your server"
        case "NOT_CONFIGURED"?, "UNKNOWN_TARGET"?:
            return "No library on your server is open for upload"
        case "TARGET_NOT_WRITABLE"?:
            return "Your server could not write to the photo folder"
        case "INSUFFICIENT_STORAGE"?:
            return "Your server has run out of space"
        case "HASH_MISMATCH"?:
            return "The photo was damaged on the way to your server"
        case "UNSUPPORTED_TYPE"?:
            return "Your server does not accept this kind of file"
        case "EMPTY_BODY"?:
            return "The photo arrived empty"
        case "TOO_LARGE"?:
            return "The photo is larger than your server accepts"
        case "INCOMPATIBLE"?:
            return "Update the upload plugin on your server"
        default:
            return "Your server refused the upload folder"
        }
    }
}

protocol UploadService: AnyObject {

    var credentials: JellyfinCredentials? { get set }
    var onTokenRejected: (() -> Void)? { get set }

    var mode: BackupMode { get set }
    var availability: BackupAvailability { get }
    var queueState: UploadQueueState { get }
    var lastSweepAt: Date? { get }
    var lastSweepResult: String? { get }

    func refreshAvailability(completion: @escaping () -> Void)
    func uploadMostRecentPhoto(completion: @escaping (Result<UploadReceipt, BackupUploadError>) -> Void)
    func enqueue(_ assets: [PHAsset])
    func resumeQueue()
    func stopQueue()
    func clearQueue()
    func performBackgroundSweep(completion: @escaping (Bool) -> Void)
    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void)
    func reset()
}

final class JellyfinUploadService: UploadService {

    private enum Key {
        static let mode = "backupMode"
        static let watermark = "backupWatermark"
        static let watermarkIdentifier = "backupWatermarkIdentifier"
        static let lastSweepAt = "backupLastSweepAt"
        static let lastSweepResult = "backupLastSweepResult"
    }

    private let client: UploadClient
    private let exporter: AssetExporter
    private let queue: UploadQueue
    private let defaults = UserDefaults.standard

    private(set) var availability: BackupAvailability = .unknown

    init(identity: DeviceIdentity) {
        let client = UploadClient(identity: identity)
        let exporter = AssetExporter()

        self.client = client
        self.exporter = exporter
        self.queue = UploadQueue(client: client, exporter: exporter)

        client.onBackgroundEventsFinished = { [weak self] in
            guard let self = self else { return }
            self.queue.persistNow()
            self.performBackgroundSweep { _ in }
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)

        client.adoptInFlight { [weak self] live in
            guard let self = self else { return }
            self.exporter.sweep(keeping: Set(live.map { AssetExporter.stagedName(for: $0) }))
            self.queue.adopt(inFlight: live)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var credentials: JellyfinCredentials? {
        get { return client.credentials }
        set { client.credentials = newValue }
    }

    var onTokenRejected: (() -> Void)? {
        get { return client.onTokenRejected }
        set { client.onTokenRejected = newValue }
    }

    var mode: BackupMode {
        get { return BackupMode(rawValue: defaults.integer(forKey: Key.mode)) ?? .off }
        set {
            if newValue == .automatic && mode != .automatic {
                defaults.set(Date(), forKey: Key.watermark)
                defaults.removeObject(forKey: Key.watermarkIdentifier)
            }
            defaults.set(newValue.rawValue, forKey: Key.mode)
        }
    }

    var queueState: UploadQueueState {
        return queue.state
    }

    var lastSweepAt: Date? {
        return defaults.object(forKey: Key.lastSweepAt) as? Date
    }

    var lastSweepResult: String? {
        return defaults.string(forKey: Key.lastSweepResult)
    }

    func refreshAvailability(completion: @escaping () -> Void) {
        client.targets { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let targets):
                self.availability = JellyfinUploadService.resolve(targets)
            case .failure(.notInstalled):
                self.availability = .notInstalled
            case .failure(.incompatible):
                self.availability = .incompatible
            case .failure(.unknown):
                break
            }
            completion()
        }
    }

    func uploadMostRecentPhoto(completion: @escaping (Result<UploadReceipt, BackupUploadError>) -> Void) {
        guard case .ready(let target) = availability else {
            completion(.failure(.notReady))
            return
        }

        exporter.exportMostRecent { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let failure):
                completion(.failure(BackupUploadError.from(failure)))
            case .success(let export):
                self.client.upload(export, targetId: target.id) { outcome in
                    self.exporter.discard(export)
                    switch outcome {
                    case .success(let receipt):
                        completion(.success(receipt))
                    case .failure(let failure):
                        completion(.failure(BackupUploadError.from(failure)))
                    }
                }
            }
        }
    }

    func enqueue(_ assets: [PHAsset]) {
        guard case .ready(let target) = availability else { return }
        queue.enqueue(assets.map { $0.localIdentifier }, targetId: target.id)
    }

    func resumeQueue() {
        let state = queue.state
        guard state.pending > 0, !state.isRunning else { return }
        guard state.stopReason != nil else {
            startQueue()
            return
        }
        refreshAvailability { [weak self] in self?.startQueue() }
    }

    func stopQueue() {
        queue.stop()
    }

    func clearQueue() {
        queue.clear()
    }

    func performBackgroundSweep(completion: @escaping (Bool) -> Void) {
        guard mode == .automatic, PHPhotoLibrary.authorizationStatus() == .authorized else {
            completion(false)
            return
        }

        refreshAvailability { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            guard case .ready = self.availability else {
                self.recordSweep("your server could not be reached")
                completion(false)
                return
            }

            let found = self.enqueueNewAssets()
            self.recordSweep(JellyfinUploadService.sweepResultText(found))
            self.queue.persistNow()
            completion(found > 0)
        }
    }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == UploadClient.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        client.storeBackgroundCompletion(completionHandler)
    }

    func reset() {
        queue.clear()
        mode = .off
        availability = .unknown
        defaults.removeObject(forKey: Key.watermark)
        defaults.removeObject(forKey: Key.watermarkIdentifier)
        defaults.removeObject(forKey: Key.lastSweepAt)
        defaults.removeObject(forKey: Key.lastSweepResult)
    }

    @objc private func applicationDidBecomeActive() {
        performBackgroundSweep { _ in }
    }

    private func enqueueNewAssets() -> Int {
        guard case .ready(let target) = availability,
              let watermark = defaults.object(forKey: Key.watermark) as? Date,
              let library = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                    subtype: .smartAlbumUserLibrary,
                                                                    options: nil).firstObject else { return 0 }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@",
                                        PHAssetMediaType.image.rawValue,
                                        watermark as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let sent = defaults.string(forKey: Key.watermarkIdentifier)
        var identifiers: [String] = []
        var lastDate: Date?

        PHAsset.fetchAssets(in: library, options: options).enumerateObjects { asset, _, _ in
            guard asset.localIdentifier != sent else { return }
            identifiers.append(asset.localIdentifier)
            lastDate = asset.creationDate ?? lastDate
        }

        guard let last = identifiers.last else { return 0 }

        queue.enqueue(identifiers, targetId: target.id)
        if let lastDate = lastDate {
            defaults.set(lastDate, forKey: Key.watermark)
        }
        defaults.set(last, forKey: Key.watermarkIdentifier)
        return identifiers.count
    }

    private func recordSweep(_ result: String) {
        defaults.set(Date(), forKey: Key.lastSweepAt)
        defaults.set(result, forKey: Key.lastSweepResult)
    }

    private static func sweepResultText(_ found: Int) -> String {
        switch found {
        case 0:
            return "nothing new"
        case 1:
            return "1 photo queued"
        default:
            return "\(found) photos queued"
        }
    }

    private func startQueue() {
        guard case .ready(let target) = availability else { return }
        queue.resume(target: target)
    }

    private static func resolve(_ targets: [UploadTarget]) -> BackupAvailability {
        guard let target = targets.first(where: { $0.id == Preferences.libraryId }) ?? targets.first else {
            return .blocked(BackupUploadError.refusalText("NOT_CONFIGURED"))
        }
        guard target.isWritable else {
            return .blocked(BackupUploadError.refusalText(target.reason))
        }
        return .ready(target)
    }
}
