import Foundation
import Security

enum KeychainRead {
    case found(Data)
    case absent
    case failed(OSStatus)
}

struct Keychain {

    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.rousseaddict.jellypic") {
        self.service = service
    }

    func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func data(for key: String) -> Data? {
        guard case .found(let data) = read(key) else { return nil }
        return data
    }

    func read(_ key: String) -> KeychainRead {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = item as? Data else {
            return .failed(status == errSecSuccess ? errSecDecode : status)
        }
        return .found(data)
    }

    @discardableResult
    func set(_ value: String, for key: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        return set(data, for: key)
    }

    @discardableResult
    func set(_ value: Data, for key: String) -> OSStatus {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else {
            return status
        }

        var insert = query
        insert.merge(attributes) { existing, _ in existing }
        return SecItemAdd(insert as CFDictionary, nil)
    }

    @discardableResult
    func remove(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
