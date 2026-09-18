import Foundation

final class JellyfinClient: JellyfinAPI {

    static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return configuration
    }

    var credentials: JellyfinCredentials?

    private let identity: DeviceIdentity
    private let session: URLSession
    private let decoder: JSONDecoder

    init(identity: DeviceIdentity,
         configuration: URLSessionConfiguration = JellyfinClient.defaultConfiguration()) {
        self.identity = identity
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = JellyfinDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Unrecognised date: \(raw)")
            }
            return date
        }
        self.decoder = decoder
    }

    func publicSystemInfo(baseURL: URL,
                          completion: @escaping (Result<PublicSystemInfo, JellyfinError>) -> Void) {
        guard let request = makeRequest(baseURL: baseURL, path: "System/Info/Public", token: nil) else {
            completion(.failure(.invalidServerURL))
            return
        }
        perform(request, as: PublicSystemInfo.self) { result in
            switch result {
            case .success(let info):
                guard info.version != nil else {
                    completion(.failure(.notAJellyfinServer))
                    return
                }
                completion(.success(info))
            case .failure(.decoding):
                completion(.failure(.notAJellyfinServer))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func authenticate(baseURL: URL,
                      username: String,
                      password: String,
                      completion: @escaping (Result<AuthenticationResult, JellyfinError>) -> Void) {
        guard var request = makeRequest(baseURL: baseURL,
                                        path: "Users/AuthenticateByName",
                                        method: "POST",
                                        token: nil) else {
            completion(.failure(.invalidServerURL))
            return
        }
        let body = ["Username": username, "Pw": password]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(.invalidServerURL))
            return
        }
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        perform(request, as: AuthenticationResult.self, completion: completion)
    }

    func libraries(completion: @escaping (Result<[JellyfinLibrary], JellyfinError>) -> Void) {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return
        }
        guard let request = makeRequest(baseURL: credentials.baseURL,
                                        path: "UserViews",
                                        query: [URLQueryItem(name: "userId", value: credentials.userId)],
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return
        }
        perform(request, as: QueryResult<JellyfinLibrary>.self) { result in
            completion(result.map { $0.items })
        }
    }

    func photos(libraryId: String,
                startIndex: Int,
                limit: Int,
                includeTotalCount: Bool,
                completion: @escaping (Result<QueryResult<PhotoDTO>, JellyfinError>) -> Void) {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return
        }
        let query = [
            URLQueryItem(name: "userId", value: credentials.userId),
            URLQueryItem(name: "parentId", value: libraryId),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "includeItemTypes", value: "Photo"),
            URLQueryItem(name: "sortBy", value: "PremiereDate,SortName"),
            URLQueryItem(name: "sortOrder", value: "Descending"),
            URLQueryItem(name: "fields", value: "DateCreated,Width,Height"),
            URLQueryItem(name: "enableImages", value: "true"),
            URLQueryItem(name: "enableImageTypes", value: "Primary"),
            URLQueryItem(name: "imageTypeLimit", value: "1"),
            URLQueryItem(name: "enableUserData", value: "false"),
            URLQueryItem(name: "enableTotalRecordCount", value: includeTotalCount ? "true" : "false"),
            URLQueryItem(name: "startIndex", value: String(startIndex)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Items",
                                        query: query,
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return
        }
        perform(request, as: QueryResult<PhotoDTO>.self, completion: completion)
    }

    func imageRequest(itemId: String, tag: String?, fillPixels: Int) -> URLRequest? {
        guard let credentials = credentials else { return nil }

        var query = [
            URLQueryItem(name: "fillWidth", value: String(fillPixels)),
            URLQueryItem(name: "fillHeight", value: String(fillPixels)),
            URLQueryItem(name: "quality", value: "80"),
            // LEGACY(ios12): WebP is undecodable here, so the output format is pinned rather than negotiated. Freed at iOS 14.
            URLQueryItem(name: "format", value: "Jpg")
        ]
        if let tag = tag {
            query.append(URLQueryItem(name: "tag", value: tag))
        }

        guard var request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Items/\(itemId)/Images/Primary",
                                        query: query,
                                        token: credentials.accessToken) else { return nil }
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    func logout(completion: @escaping (Result<Void, JellyfinError>) -> Void) {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return
        }
        guard let request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Sessions/Logout",
                                        method: "POST",
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return
        }
        performIgnoringBody(request, completion: completion)
    }

    private func makeRequest(baseURL: URL,
                             path: String,
                             query: [URLQueryItem] = [],
                             method: String = "GET",
                             token: String?) -> URLRequest? {
        let target = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorizationHeader(token: token), forHTTPHeaderField: "Authorization")
        return request
    }

    private func authorizationHeader(token: String?) -> String {
        var fields: [String] = []
        if let token = token {
            fields.append("Token=\"\(sanitized(token))\"")
        }
        fields.append("Client=\"\(sanitized(identity.client))\"")
        fields.append("Device=\"\(sanitized(identity.device))\"")
        fields.append("DeviceId=\"\(sanitized(identity.deviceId))\"")
        fields.append("Version=\"\(sanitized(identity.version))\"")
        return "MediaBrowser " + fields.joined(separator: ", ")
    }

    private func sanitized(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\"\\,\r\n")
        let cleaned = value.components(separatedBy: forbidden).joined()
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    private func perform<T: Decodable>(_ request: URLRequest,
                                       as type: T.Type,
                                       completion: @escaping (Result<T, JellyfinError>) -> Void) {
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let failure = self.failure(response: response, error: error) {
                self.finish(.failure(failure), completion)
                return
            }
            guard let data = data, !data.isEmpty else {
                self.finish(.failure(.emptyResponse), completion)
                return
            }
            do {
                let value = try self.decoder.decode(T.self, from: data)
                self.finish(.success(value), completion)
            } catch {
                self.finish(.failure(.decoding(error)), completion)
            }
        }.resume()
    }

    private func performIgnoringBody(_ request: URLRequest,
                                     completion: @escaping (Result<Void, JellyfinError>) -> Void) {
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            if let failure = self.failure(response: response, error: error) {
                self.finish(.failure(failure), completion)
            } else {
                self.finish(.success(()), completion)
            }
        }.resume()
    }

    private func failure(response: URLResponse?, error: Error?) -> JellyfinError? {
        if let urlError = error as? URLError {
            if urlError.code == .appTransportSecurityRequiresSecureConnection {
                return .appTransportSecurity
            }
            return .unreachable(urlError)
        }
        if let error = error {
            return .transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            return .emptyResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            return .httpStatus(http.statusCode)
        }
        return nil
    }

    private func finish<T>(_ result: Result<T, JellyfinError>,
                           _ completion: @escaping (Result<T, JellyfinError>) -> Void) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
