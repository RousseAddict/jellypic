import Foundation
import Security

final class AuthStore {

    private enum Key {
        static let deviceId = "deviceId"
        static let serverURL = "serverURL"
        static let accessToken = "accessToken"
        static let userId = "userId"
        static let serverId = "serverId"
        static let username = "username"
    }

    private let keychain: Keychain

    let deviceId: String
    private let deviceIdStatus: OSStatus

    init(keychain: Keychain = Keychain()) {
        self.keychain = keychain

        if let existing = keychain.string(for: Key.deviceId), !existing.isEmpty {
            self.deviceId = existing
            self.deviceIdStatus = errSecSuccess
        } else {
            let generated = UUID().uuidString
            self.deviceId = generated
            self.deviceIdStatus = keychain.set(generated, for: Key.deviceId)
        }
    }

    var session: JellyfinSession? {
        guard let address = keychain.string(for: Key.serverURL),
              let baseURL = URL(string: address),
              let userId = keychain.string(for: Key.userId) else { return nil }

        return JellyfinSession(baseURL: baseURL,
                               userId: userId,
                               username: nonEmpty(Key.username),
                               serverId: nonEmpty(Key.serverId))
    }

    var credentials: JellyfinCredentials? {
        guard let address = keychain.string(for: Key.serverURL),
              let baseURL = URL(string: address),
              let accessToken = keychain.string(for: Key.accessToken),
              let userId = keychain.string(for: Key.userId) else { return nil }

        return JellyfinCredentials(baseURL: baseURL,
                                   accessToken: accessToken,
                                   userId: userId,
                                   serverId: nonEmpty(Key.serverId))
    }

    @discardableResult
    func save(_ credentials: JellyfinCredentials, username: String) -> OSStatus {
        var writes = [
            deviceIdStatus,
            keychain.set(credentials.baseURL.absoluteString, for: Key.serverURL),
            keychain.set(credentials.accessToken, for: Key.accessToken),
            keychain.set(credentials.userId, for: Key.userId),
            keychain.set(username, for: Key.username)
        ]
        if let serverId = credentials.serverId {
            writes.append(keychain.set(serverId, for: Key.serverId))
        } else {
            keychain.remove(Key.serverId)
        }
        guard let failure = writes.first(where: { $0 != errSecSuccess }) else {
            return errSecSuccess
        }
        clearToken()
        return failure
    }

    func clearToken() {
        keychain.remove(Key.accessToken)
    }

    func clear() {
        keychain.remove(Key.serverURL)
        keychain.remove(Key.accessToken)
        keychain.remove(Key.userId)
        keychain.remove(Key.serverId)
        keychain.remove(Key.username)
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let value = keychain.string(for: key), !value.isEmpty else { return nil }
        return value
    }
}
