import Foundation

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
    case refused(String)
}

protocol UploadService: AnyObject {

    var credentials: JellyfinCredentials? { get set }
    var onTokenRejected: (() -> Void)? { get set }

    var mode: BackupMode { get set }
    var availability: BackupAvailability { get }

    func refreshAvailability(completion: @escaping () -> Void)
    func uploadMostRecentPhoto(completion: @escaping (Result<UploadReceipt, BackupUploadError>) -> Void)
    func reset()
}

final class JellyfinUploadService: UploadService {

    private enum Key {
        static let mode = "backupMode"
    }

    private let client: UploadClient
    private let exporter = AssetExporter()
    private let defaults = UserDefaults.standard

    private(set) var availability: BackupAvailability = .unknown

    init(identity: DeviceIdentity) {
        client = UploadClient(identity: identity)

        let exporter = self.exporter
        DispatchQueue.global(qos: .utility).async { exporter.sweep() }
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
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
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
                completion(.failure(JellyfinUploadService.translate(failure)))
            case .success(let export):
                self.client.upload(export, targetId: target.id) { outcome in
                    self.exporter.discard(export)
                    switch outcome {
                    case .success(let receipt):
                        completion(.success(receipt))
                    case .failure(let failure):
                        completion(.failure(JellyfinUploadService.translate(failure)))
                    }
                }
            }
        }
    }

    func reset() {
        mode = .off
        availability = .unknown
    }

    private static func translate(_ failure: AssetExportFailure) -> BackupUploadError {
        switch failure {
        case .denied:
            return .permissionDenied
        case .noAsset, .noResource, .notLocal:
            return .photoUnavailable
        case .write:
            return .refused("Could not stage the photo on this device")
        }
    }

    private static func translate(_ failure: UploadFailure) -> BackupUploadError {
        switch failure {
        case .unauthorized:
            return .unauthorized
        case .transient:
            return .refused("Your server did not answer")
        case .stopQueue(let code), .rejected(let code):
            return .refused(refusalText(code))
        }
    }

    private static func resolve(_ targets: [UploadTarget]) -> BackupAvailability {
        guard let target = targets.first(where: { $0.id == Preferences.libraryId }) ?? targets.first else {
            return .blocked(refusalText("NOT_CONFIGURED"))
        }
        guard target.isWritable else { return .blocked(refusalText(target.reason)) }
        return .ready(target)
    }

    private static func refusalText(_ reason: String?) -> String {
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
