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
    var cachedImageBaseURL: URL?
    var onTokenRejected: (() -> Void)?

    private let identity: DeviceIdentity
    private let session: URLSession
    private let decoder: JSONDecoder
    private let downloader = FileDownloader()

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
                minDateLastSaved: Date?,
                completion: @escaping (Result<PhotoPage, JellyfinError>) -> Void) -> URLSessionTask? {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return nil
        }
        var query = [
            URLQueryItem(name: "userId", value: credentials.userId),
            URLQueryItem(name: "parentId", value: libraryId),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "includeItemTypes", value: "Photo,Video"),
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
        if let minDateLastSaved = minDateLastSaved {
            query.append(URLQueryItem(name: "minDateLastSaved",
                                      value: JellyfinDate.format(minDateLastSaved)))
        }
        guard let request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Items",
                                        query: query,
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return nil
        }
        return perform(request, as: QueryResult<PhotoDTO>.self, mapping: { result, response in
            PhotoPage(items: result.items,
                      totalRecordCount: result.totalRecordCount,
                      serverDate: JellyfinClient.serverDate(from: response))
        }, completion: completion)
    }

    func imageRequest(itemId: String, tag: String?, fillPixels: Int) -> URLRequest? {
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
        return primaryImageRequest(itemId: itemId, query: query)
    }

    func fullImageRequest(itemId: String, tag: String?, maxPixels: Int) -> URLRequest? {
        var query = [
            URLQueryItem(name: "maxWidth", value: String(maxPixels)),
            URLQueryItem(name: "maxHeight", value: String(maxPixels)),
            URLQueryItem(name: "quality", value: "90"),
            // LEGACY(ios12): WebP is undecodable here, so the output format is pinned rather than negotiated. Freed at iOS 14.
            URLQueryItem(name: "format", value: "Jpg")
        ]
        if let tag = tag {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        return primaryImageRequest(itemId: itemId, query: query)
    }

    private func primaryImageRequest(itemId: String, query: [URLQueryItem]) -> URLRequest? {
        guard let baseURL = credentials?.baseURL ?? cachedImageBaseURL,
              var request = makeRequest(baseURL: baseURL,
                                        path: "Items/\(itemId)/Images/Primary",
                                        query: query,
                                        token: credentials?.accessToken) else { return nil }
        request.cachePolicy = credentials == nil ? .returnCacheDataDontLoad : .returnCacheDataElseLoad
        return request
    }

    func photoDetails(itemId: String,
                      completion: @escaping (Result<PhotoDetailsDTO, JellyfinError>) -> Void) -> URLSessionTask? {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return nil
        }
        guard let request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Items/\(itemId)",
                                        query: [URLQueryItem(name: "userId", value: credentials.userId)],
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return nil
        }
        return perform(request, as: PhotoDetailsDTO.self, completion: completion)
    }

    func originalFileSize(itemId: String, completion: @escaping (Int64?) -> Void) -> URLSessionTask? {
        guard var request = originalFileRequest(itemId: itemId) else {
            completion(nil)
            return nil
        }
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            if let failure = self?.failure(response: response, error: error) {
                self?.reportIfTokenRejected(failure, on: request)
            }
            let size = JellyfinClient.totalBytes(from: response as? HTTPURLResponse)
            DispatchQueue.main.async {
                completion(size)
            }
        }
        task.resume()
        return task
    }

    func playbackInfo(itemId: String,
                      deviceProfile: [String: Any],
                      completion: @escaping (Result<PlaybackInfoResponse, JellyfinError>) -> Void) -> URLSessionTask? {
        guard let credentials = credentials else {
            completion(.failure(.notAuthenticated))
            return nil
        }
        guard var request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Items/\(itemId)/PlaybackInfo",
                                        method: "POST",
                                        token: credentials.accessToken) else {
            completion(.failure(.invalidServerURL))
            return nil
        }
        let body: [String: Any] = [
            "UserId": credentials.userId,
            "DeviceProfile": deviceProfile,
            "AutoOpenLiveStream": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(.invalidServerURL))
            return nil
        }
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return perform(request, as: PlaybackInfoResponse.self, completion: completion)
    }

    func directPlayURL(itemId: String, mediaSourceId: String?, playSessionId: String?) -> URL? {
        guard let credentials = credentials else { return nil }
        var query = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: credentials.accessToken)
        ]
        if let mediaSourceId = mediaSourceId {
            query.append(URLQueryItem(name: "mediaSourceId", value: mediaSourceId))
        }
        if let playSessionId = playSessionId {
            query.append(URLQueryItem(name: "playSessionId", value: playSessionId))
        }
        let target = credentials.baseURL.appendingPathComponent("Videos/\(itemId)/stream")
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = query
        return components.url
    }

    func transcodedStreamURL(serverPath: String) -> URL? {
        guard let credentials = credentials,
              let source = URLComponents(string: serverPath),
              source.scheme == nil,
              source.host == nil else { return nil }
        let segments = source.path.components(separatedBy: "/").filter { !$0.isEmpty }
        guard !segments.isEmpty, !segments.contains("..") else { return nil }

        var target = credentials.baseURL
        for segment in segments {
            target.appendPathComponent(segment)
        }
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return nil }
        components.percentEncodedQuery = source.percentEncodedQuery
        return components.url
    }

    func reportPlaybackStopped(itemId: String, playSessionId: String) {
        guard let credentials = credentials else { return }
        guard var request = makeRequest(baseURL: credentials.baseURL,
                                        path: "Sessions/Playing/Stopped",
                                        method: "POST",
                                        token: credentials.accessToken) else { return }
        let body: [String: Any] = ["ItemId": itemId, "PlaySessionId": playSessionId]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return }
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        performIgnoringBody(request) { _ in }
    }

    func downloadOriginal(itemId: String,
                          fileName: String,
                          progress: @escaping (Int64, Int64) -> Void,
                          completion: @escaping (Result<URL, JellyfinError>) -> Void) -> URLSessionTask? {
        guard let request = originalFileRequest(itemId: itemId) else {
            finish(.failure(.notAuthenticated), completion)
            return nil
        }
        return downloader.download(request,
                                   fileName: fileName,
                                   progress: progress) { [weak self] result in
            if case .failure(let error) = result {
                self?.reportIfTokenRejected(error, on: request)
            }
            completion(result)
        }
    }

    private func originalFileRequest(itemId: String) -> URLRequest? {
        guard let credentials = credentials else { return nil }
        return makeRequest(baseURL: credentials.baseURL,
                           path: "Items/\(itemId)/File",
                           token: credentials.accessToken)
    }

    private static func totalBytes(from response: HTTPURLResponse?) -> Int64? {
        guard let response = response else { return nil }
        if let range = header("Content-Range", in: response),
           let total = range.components(separatedBy: "/").last,
           let bytes = Int64(total.trimmingCharacters(in: .whitespaces)), bytes > 0 {
            return bytes
        }
        guard response.statusCode == 200, response.expectedContentLength > 0 else { return nil }
        return response.expectedContentLength
    }

    // LEGACY(ios12): HTTPURLResponse.value(forHTTPHeaderField:) is iOS 13+. Freed at iOS 13.
    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String
            }
        }
        return nil
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
        request.setValue(jellyfinAuthorization(identity: identity, token: token),
                         forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    private func perform<T: Decodable>(_ request: URLRequest,
                                       as type: T.Type,
                                       completion: @escaping (Result<T, JellyfinError>) -> Void) -> URLSessionTask {
        return perform(request, as: type, mapping: { value, _ in value }, completion: completion)
    }

    private func perform<T: Decodable, R>(_ request: URLRequest,
                                          as type: T.Type,
                                          mapping: @escaping (T, HTTPURLResponse?) -> R,
                                          completion: @escaping (Result<R, JellyfinError>) -> Void) -> URLSessionTask {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let failure = self.failure(response: response, error: error) {
                self.reportIfTokenRejected(failure, on: request)
                self.finish(.failure(failure), completion)
                return
            }
            guard let data = data, !data.isEmpty else {
                self.finish(.failure(.emptyResponse), completion)
                return
            }
            do {
                let value = try self.decoder.decode(T.self, from: data)
                self.finish(.success(mapping(value, response as? HTTPURLResponse)), completion)
            } catch {
                self.finish(.failure(.decoding(error)), completion)
            }
        }
        task.resume()
        return task
    }

    private static func serverDate(from response: HTTPURLResponse?) -> Date? {
        guard let raw = response?.allHeaderFields["Date"] as? String else { return nil }
        return JellyfinDate.parseHeader(raw)
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

    private func reportIfTokenRejected(_ failure: JellyfinError, on request: URLRequest) {
        guard case .unauthorized = failure,
              let header = request.value(forHTTPHeaderField: "Authorization"),
              header.contains("Token=\"") else { return }
        DispatchQueue.main.async { self.onTokenRejected?() }
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
