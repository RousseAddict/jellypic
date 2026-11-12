import Foundation

enum DeleteCapability {
    case unknown
    case allowed
    case notPermitted

    func note(account: String?, library: String?) -> String? {
        let library = library ?? "this library"
        switch self {
        case .unknown:
            return nil
        case .allowed:
            let who = account ?? "This account"
            return "\(who) can delete photos from \(library)\n"
                + "A deleted photo is removed from your server for good"
        case .notPermitted:
            let who = account ?? "this account"
            let path = "Users → \(account ?? "your account") → Allow media deletion from"
            return "Deleting is off: \(who) isn't allowed to delete from \(library)\n"
                + "An administrator can turn it on in the Jellyfin dashboard, under \(path)"
        }
    }
}

enum DeleteOutcome {
    case removed
    case notPermitted
    case sessionExpired
    case serverRefused
    case unreachable
    case unexpected

    var text: String? {
        switch self {
        case .removed, .notPermitted, .sessionExpired:
            return nil
        case .serverRefused:
            return "The server couldn't delete the file. Check that Jellyfin can write to the library folder."
        case .unreachable:
            return "The server didn't answer. Try again."
        case .unexpected:
            return "The server answered in a way Jellypic didn't expect. Try again."
        }
    }
}

protocol DeleteService: AnyObject {

    var credentials: JellyfinCredentials? { get set }
    var onTokenRejected: (() -> Void)? { get set }

    var capability: DeleteCapability { get }

    func refreshCapability(completion: @escaping () -> Void)
    func delete(itemId: String, completion: @escaping (DeleteOutcome) -> Void)
    func reset()
}

final class JellyfinDeleteService: DeleteService {

    private struct ProbePayload: Decodable {
        let items: [Item]

        enum CodingKeys: String, CodingKey {
            case items = "Items"
        }

        struct Item: Decodable {
            let canDelete: Bool?

            enum CodingKeys: String, CodingKey {
                case canDelete = "CanDelete"
            }
        }
    }

    var credentials: JellyfinCredentials?
    var onTokenRejected: (() -> Void)?

    private(set) var capability: DeleteCapability = .unknown

    private let identity: DeviceIdentity
    private let session: URLSession
    private var generation = 0

    init(identity: DeviceIdentity) {
        self.identity = identity

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)
    }

    func refreshCapability(completion: @escaping () -> Void) {
        guard let credentials = credentials,
              let libraryId = Preferences.libraryId,
              let request = probeRequest(credentials: credentials, libraryId: libraryId) else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        let generation = self.generation
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if generation == self.generation,
                   let verdict = self.verdict(data: data, response: response, error: error) {
                    self.capability = verdict
                }
                completion()
            }
        }.resume()
    }

    func delete(itemId: String, completion: @escaping (DeleteOutcome) -> Void) {
        guard let credentials = credentials else {
            DispatchQueue.main.async { completion(.sessionExpired) }
            return
        }

        var request = URLRequest(url: credentials.baseURL
            .appendingPathComponent("Items")
            .appendingPathComponent(itemId))
        request.httpMethod = "DELETE"
        request.setValue(jellyfinAuthorization(identity: identity, token: credentials.accessToken),
                         forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.settle(response: response, error: error, completion: completion)
            }
        }.resume()
    }

    func reset() {
        generation += 1
        capability = .unknown
    }

    private func settle(response: URLResponse?,
                        error: Error?,
                        completion: @escaping (DeleteOutcome) -> Void) {
        guard error == nil, let http = response as? HTTPURLResponse else {
            completion(.unreachable)
            return
        }
        switch http.statusCode {
        case 200..<300, 404:
            completion(.removed)
        case 401:
            settleRefusal(completion: completion)
        case 500..<600:
            completion(.serverRefused)
        default:
            completion(.unexpected)
        }
    }

    private func settleRefusal(completion: @escaping (DeleteOutcome) -> Void) {
        refreshCapability { [weak self] in
            guard let self = self else { return }
            guard self.credentials != nil else {
                completion(.sessionExpired)
                return
            }
            completion(self.capability == .notPermitted ? .notPermitted : .unexpected)
        }
    }

    private func probeRequest(credentials: JellyfinCredentials, libraryId: String) -> URLRequest? {
        guard var components = URLComponents(url: credentials.baseURL.appendingPathComponent("Items"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "userId", value: credentials.userId),
            URLQueryItem(name: "parentId", value: libraryId),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "includeItemTypes", value: "Photo"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "fields", value: "CanDelete"),
            URLQueryItem(name: "enableImages", value: "false"),
            URLQueryItem(name: "enableUserData", value: "false"),
            URLQueryItem(name: "enableTotalRecordCount", value: "false")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(jellyfinAuthorization(identity: identity, token: credentials.accessToken),
                         forHTTPHeaderField: "Authorization")
        return request
    }

    private func verdict(data: Data?, response: URLResponse?, error: Error?) -> DeleteCapability? {
        guard error == nil, let http = response as? HTTPURLResponse else { return nil }

        if HTTPStatus.rejectsToken(http.statusCode) {
            onTokenRejected?()
            return nil
        }
        guard (200..<300).contains(http.statusCode),
              let data = data,
              let payload = try? JSONDecoder().decode(ProbePayload.self, from: data) else { return nil }

        guard let item = payload.items.first else { return .unknown }
        switch item.canDelete {
        case true?:
            return .allowed
        case false?:
            return .notPermitted
        case nil:
            return nil
        }
    }
}
