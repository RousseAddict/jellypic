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

protocol UploadService: AnyObject {

    var credentials: JellyfinCredentials? { get set }
    var onTokenRejected: (() -> Void)? { get set }

    var mode: BackupMode { get set }
    var availability: BackupAvailability { get }

    func refreshAvailability(completion: @escaping () -> Void)
    func reset()
}

final class JellyfinUploadService: UploadService {

    private enum Key {
        static let mode = "backupMode"
    }

    private let client: UploadClient
    private let defaults = UserDefaults.standard

    private(set) var availability: BackupAvailability = .unknown

    init(identity: DeviceIdentity) {
        client = UploadClient(identity: identity)
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

    func reset() {
        mode = .off
        availability = .unknown
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
        case "NOT_CONFIGURED"?:
            return "No library on your server is open for upload"
        default:
            return "Your server refused the upload folder"
        }
    }
}
