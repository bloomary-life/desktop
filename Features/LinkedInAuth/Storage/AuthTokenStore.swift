import Foundation
import Security

protocol LinkedInTokenStore {
    func load() -> LinkedInToken?
    func save(_ token: LinkedInToken)
    func clear()
    func clearAccountDeletionData()
}

extension LinkedInTokenStore {
    func clearAccountDeletionData() {
        clear()
    }
}

final class AuthTokenStore: LinkedInTokenStore {
    private let key: String
    private let service = "com.dailymind.bloomary.desktop.linkedin"

    init(key: String) {
        self.key = key
    }

    func load() -> LinkedInToken? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder.app.decode(LinkedInToken.self, from: data)
    }

    func save(_ token: LinkedInToken) {
        guard let data = try? JSONEncoder.app.encode(token) else { return }
        var query = keychainQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(keychainQuery as CFDictionary)
    }

    func clearAccountDeletionData() {
        clear()
        var synchronizableQuery = keychainQuery
        synchronizableQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(synchronizableQuery as CFDictionary)
    }

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
