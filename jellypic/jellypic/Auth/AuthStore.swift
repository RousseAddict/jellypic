import Foundation
import Security

final class AuthStore {

    private enum Key {
        static let deviceId = "deviceId"
        static let serverURL = "serverURL"
        static let accessToken = "accessToken"
        static let userId = "userId"
        static let serverId = "serverId"
    }

    private let keychain: Keychain

    init(keychain: Keychain = Keychain()) {
        self.keychain = keychain
    }

    var deviceId: String {
        if let existing = keychain.string(for: Key.deviceId), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        keychain.set(generated, for: Key.deviceId)
        return generated
    }

    var credentials: JellyfinCredentials? {
        guard let address = keychain.string(for: Key.serverURL),
              let baseURL = URL(string: address),
              let accessToken = keychain.string(for: Key.accessToken),
              let userId = keychain.string(for: Key.userId) else { return nil }

        return JellyfinCredentials(baseURL: baseURL,
                                   accessToken: accessToken,
                                   userId: userId,
                                   serverId: keychain.string(for: Key.serverId))
    }

    @discardableResult
    func save(_ credentials: JellyfinCredentials) -> OSStatus {
        let writes = [
            keychain.set(credentials.baseURL.absoluteString, for: Key.serverURL),
            keychain.set(credentials.accessToken, for: Key.accessToken),
            keychain.set(credentials.userId, for: Key.userId)
        ]
        if let failure = writes.first(where: { $0 != errSecSuccess }) {
            return failure
        }
        if let serverId = credentials.serverId {
            keychain.set(serverId, for: Key.serverId)
        } else {
            keychain.remove(Key.serverId)
        }
        return errSecSuccess
    }

    func clear() {
        keychain.remove(Key.serverURL)
        keychain.remove(Key.accessToken)
        keychain.remove(Key.userId)
        keychain.remove(Key.serverId)
    }
}
