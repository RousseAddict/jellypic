import Foundation

struct UploadTarget {
    let id: String
    let name: String
    let isWritable: Bool
    let reason: String?
}

enum UploadProbeFailure: Error {
    case notInstalled
    case incompatible
    case unknown
}

struct UploadReceipt {
    let key: String
    let path: String
    let created: Bool
}

enum UploadFailure: Error {
    case unauthorized
    case stopQueue(String)
    case rejected(String)
    case transient
    case offline
}

final class UploadClient {

    private struct TargetsPayload: Decodable {
        let targets: [Entry]

        struct Entry: Decodable {
            let id: String
            let name: String
            let writable: Bool
            let reason: String?
        }
    }

    private struct ItemPayload: Decodable {
        let key: String
        let path: String
        let created: Bool
    }

    private struct ErrorPayload: Decodable {
        let code: String
    }

    var credentials: JellyfinCredentials?
    var onTokenRejected: (() -> Void)?

    private let identity: DeviceIdentity
    private let session: URLSession
    private let uploadSession: URLSession

    init(identity: DeviceIdentity) {
        self.identity = identity

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)

        let uploadConfiguration = URLSessionConfiguration.default
        uploadConfiguration.timeoutIntervalForRequest = 60
        uploadConfiguration.timeoutIntervalForResource = 3600
        uploadConfiguration.allowsCellularAccess = false
        uploadConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        uploadConfiguration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.uploadSession = URLSession(configuration: uploadConfiguration)
    }

    @discardableResult
    func targets(completion: @escaping (Result<[UploadTarget], UploadProbeFailure>) -> Void) -> URLSessionTask? {
        guard let credentials = credentials else {
            finish(.failure(.unknown), completion)
            return nil
        }
        var request = URLRequest(url: credentials.baseURL.appendingPathComponent("UploadForJelly/Targets"))
        request.setValue(jellyfinAuthorization(identity: identity, token: credentials.accessToken),
                         forHTTPHeaderField: "Authorization")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.finish(self.outcome(data: data, response: response, error: error), completion)
        }
        task.resume()
        return task
    }

    @discardableResult
    func upload(_ export: AssetExport,
                targetId: String,
                completion: @escaping (Result<UploadReceipt, UploadFailure>) -> Void) -> URLSessionTask? {
        guard let credentials = credentials,
              let url = itemsURL(baseURL: credentials.baseURL, export: export, targetId: targetId) else {
            finish(.failure(.rejected("BAD_REQUEST")), completion)
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(jellyfinAuthorization(identity: identity, token: credentials.accessToken),
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let task = uploadSession.uploadTask(with: request, fromFile: export.fileURL) { [weak self] data, response, error in
            guard let self = self else { return }
            self.finish(self.receipt(data: data, response: response, error: error), completion)
        }
        task.resume()
        return task
    }

    private func itemsURL(baseURL: URL, export: AssetExport, targetId: String) -> URL? {
        let endpoint = baseURL.appendingPathComponent("UploadForJelly/Items")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }

        var items = [URLQueryItem(name: "targetId", value: targetId),
                     URLQueryItem(name: "sha256", value: export.sha256),
                     URLQueryItem(name: "deviceSlug", value: UploadClient.deviceSlug),
                     URLQueryItem(name: "fileName", value: export.fileName)]
        if let capturedAt = export.capturedAt {
            items.append(URLQueryItem(name: "capturedAt",
                                      value: UploadClient.capturedAtFormatter.string(from: capturedAt)))
        }
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    private func receipt(data: Data?,
                         response: URLResponse?,
                         error: Error?) -> Result<UploadReceipt, UploadFailure> {
        if let error = error as NSError?,
           error.domain == NSURLErrorDomain,
           error.code == NSURLErrorDataNotAllowed {
            return .failure(.offline)
        }
        guard error == nil, let http = response as? HTTPURLResponse else { return .failure(.transient) }

        if http.statusCode == 401 || http.statusCode == 403 {
            DispatchQueue.main.async { self.onTokenRejected?() }
            return .failure(.unauthorized)
        }

        if (200..<300).contains(http.statusCode) {
            guard let data = data,
                  let payload = try? JSONDecoder().decode(ItemPayload.self, from: data) else {
                return .failure(.rejected("INCOMPATIBLE"))
            }
            return .success(UploadReceipt(key: payload.key, path: payload.path, created: payload.created))
        }

        let isTerminal = (400..<500).contains(http.statusCode) || http.statusCode == 507
        guard isTerminal else { return .failure(.transient) }

        let code = data.flatMap { try? JSONDecoder().decode(ErrorPayload.self, from: $0) }?.code
            ?? UploadClient.fallbackCode(for: http.statusCode)

        switch http.statusCode {
        case 404, 409, 507:
            return .failure(.stopQueue(code))
        default:
            return .failure(.rejected(code))
        }
    }

    private static func fallbackCode(for status: Int) -> String {
        switch status {
        case 404:
            return "UNKNOWN_TARGET"
        case 409:
            return "TARGET_NOT_WRITABLE"
        case 413:
            return "TOO_LARGE"
        case 507:
            return "INSUFFICIENT_STORAGE"
        default:
            return "BAD_REQUEST"
        }
    }

    private static let capturedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    private static let deviceSlug: String = {
        var info = utsname()
        uname(&info)
        let machine = Mirror(reflecting: info.machine).children.reduce(into: "") { result, element in
            guard let byte = element.value as? Int8, byte != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(byte))))
        }
        return machine.isEmpty ? "iphone" : machine
    }()

    private func outcome(data: Data?,
                         response: URLResponse?,
                         error: Error?) -> Result<[UploadTarget], UploadProbeFailure> {
        guard error == nil, let http = response as? HTTPURLResponse else { return .failure(.unknown) }

        if http.statusCode == 401 || http.statusCode == 403 {
            DispatchQueue.main.async { self.onTokenRejected?() }
            return .failure(.unknown)
        }
        if http.statusCode == 404 {
            return .failure(.notInstalled)
        }
        guard (200..<300).contains(http.statusCode) else { return .failure(.unknown) }
        guard let data = data,
              let payload = try? JSONDecoder().decode(TargetsPayload.self, from: data) else {
            return .failure(.incompatible)
        }
        return .success(payload.targets.map {
            UploadTarget(id: $0.id, name: $0.name, isWritable: $0.writable, reason: $0.reason)
        })
    }

    private func finish<T>(_ result: T, _ completion: @escaping (T) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }
}
