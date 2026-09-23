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

    var credentials: JellyfinCredentials?
    var onTokenRejected: (() -> Void)?

    private let identity: DeviceIdentity
    private let session: URLSession

    init(identity: DeviceIdentity) {
        self.identity = identity

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)
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
