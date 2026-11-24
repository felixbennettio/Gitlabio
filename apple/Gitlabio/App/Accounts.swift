import Foundation
import Security
import GitLabCore

/// Non-secret account metadata, persisted in UserDefaults. Tokens live in the Keychain.
struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var instance: GitLabInstance
    var userID: Int
    var username: String
    var name: String
    var avatarUrl: String?
    var trust: TrustPolicy = .system
    var scopes: [String]?
    var tokenExpiresAt: String?
    var addedAt = Date()

    var handle: String { "@\(username)" }
    var canWrite: Bool { scopes.map { $0.contains("api") } ?? true }
}

enum Keychain {
    private static let service = "io.routeforge.gitlabio.token"

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    static func save(_ token: String, for id: UUID) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query(id).merging(attributes) { $1 } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func token(for id: UUID) throws -> String {
        var lookup = query(id)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return token
    }

    static func delete(_ id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            status == errSecItemNotFound ? "找不到此账户的令牌，请重新登录。" : "无法访问钥匙串（\(status)）。请解锁设备后重试。"
        }
    }
}
