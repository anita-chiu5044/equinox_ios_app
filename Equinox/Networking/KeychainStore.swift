import Foundation
import Security

final class KeychainStore {
    private let service: String
    private let account: String
    private static var inMemoryToken: String?

    init(service: String = "com.equinox.app", account: String = "access-token") {
        self.service = service
        self.account = account
    }

    func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return Self.inMemoryToken
        }

        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        Self.inMemoryToken = token
        let data = Data(token.utf8)
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func delete() {
        Self.inMemoryToken = nil
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
