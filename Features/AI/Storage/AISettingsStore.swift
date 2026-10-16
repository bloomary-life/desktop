import Foundation
import Security

struct AISettings {
    let apiKey: String
}

protocol AIAPIKeyStore {
    func load() -> String?
    func save(_ apiKey: String) -> Bool
    func clear() -> Bool
}

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var apiKey: String
    @Published private(set) var statusMessage: String?

    private let keyStore: AIAPIKeyStore

    init(keyStore: AIAPIKeyStore = KeychainAIAPIKeyStore()) {
        self.keyStore = keyStore
        self.apiKey = keyStore.load() ?? ""
    }

    var current: AISettings {
        AISettings(apiKey: apiKey)
    }

    func save() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmedKey
        let saved: Bool
        if trimmedKey.isEmpty {
            saved = keyStore.clear()
        } else {
            saved = keyStore.save(trimmedKey)
        }
        statusMessage = saved ? "AI settings saved." : "AI key could not be saved."
    }

    func clearAccountDeletionData() {
        _ = keyStore.clear()
        apiKey = ""
    }
}

final class KeychainAIAPIKeyStore: AIAPIKeyStore {
    private let key = "ai-api-key"
    private let service = "com.dailymind.bloomary.desktop.ai"

    func load() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        var query = keychainQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    func clear() -> Bool {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        var synchronizableQuery = keychainQuery
        synchronizableQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let syncStatus = SecItemDelete(synchronizableQuery as CFDictionary)
        return (status == errSecSuccess || status == errSecItemNotFound) &&
            (syncStatus == errSecSuccess || syncStatus == errSecItemNotFound)
    }

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
