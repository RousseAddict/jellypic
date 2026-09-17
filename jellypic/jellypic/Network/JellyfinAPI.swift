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

protocol JellyfinAPI: AnyObject {

    var credentials: JellyfinCredentials? { get set }

    func publicSystemInfo(baseURL: URL,
                          completion: @escaping (Result<PublicSystemInfo, JellyfinError>) -> Void)

    func authenticate(baseURL: URL,
                      username: String,
                      password: String,
                      completion: @escaping (Result<AuthenticationResult, JellyfinError>) -> Void)

    func libraries(completion: @escaping (Result<[JellyfinLibrary], JellyfinError>) -> Void)

    func logout(completion: @escaping (Result<Void, JellyfinError>) -> Void)
}
