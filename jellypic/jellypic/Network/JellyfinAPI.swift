import Foundation

struct DeviceIdentity {
    let client: String
    let device: String
    let deviceId: String
    let version: String
}

struct JellyfinCredentials {
    let baseURL: URL
    let accessToken: String
    let userId: String
    let serverId: String?
}

struct JellyfinSession {
    let baseURL: URL
    let userId: String
    let username: String?
    let serverId: String?
}

// LEGACY(ios12): every method below is completion-based because Swift Concurrency back-deploys only to iOS 13 — this whole protocol is the swap surface. Freed at iOS 13.
protocol JellyfinAPI: AnyObject {

    var credentials: JellyfinCredentials? { get set }
    var cachedImageBaseURL: URL? { get set }
    var onTokenRejected: (() -> Void)? { get set }

    func publicSystemInfo(baseURL: URL,
                          completion: @escaping (Result<PublicSystemInfo, JellyfinError>) -> Void)

    func authenticate(baseURL: URL,
                      username: String,
                      password: String,
                      completion: @escaping (Result<AuthenticationResult, JellyfinError>) -> Void)

    func libraries(completion: @escaping (Result<[JellyfinLibrary], JellyfinError>) -> Void)

    func photos(libraryId: String,
                startIndex: Int,
                limit: Int,
                includeTotalCount: Bool,
                completion: @escaping (Result<QueryResult<PhotoDTO>, JellyfinError>) -> Void) -> URLSessionTask?

    func imageRequest(itemId: String, tag: String?, fillPixels: Int) -> URLRequest?

    func fullImageRequest(itemId: String, tag: String?, maxPixels: Int) -> URLRequest?

    func photoDetails(itemId: String,
                      completion: @escaping (Result<PhotoDetailsDTO, JellyfinError>) -> Void) -> URLSessionTask?

    func originalFileSize(itemId: String, completion: @escaping (Int64?) -> Void) -> URLSessionTask?

    func downloadOriginal(itemId: String,
                          fileName: String,
                          progress: @escaping (Int64, Int64) -> Void,
                          completion: @escaping (Result<URL, JellyfinError>) -> Void) -> URLSessionTask?

    func logout(completion: @escaping (Result<Void, JellyfinError>) -> Void)
}
