//
//  SupabaseSessionStore.swift
//  monitor_helper
//

import Foundation
import Security

struct StoredSupabaseSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let userID: String?
    let userEmail: String?

    var isRefreshable: Bool {
        refreshToken?.isEmpty == false
    }

    func isExpiringSoon(buffer: TimeInterval = 120, now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= buffer
    }
}

enum SupabaseSessionStoreError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case keychainFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "The Supabase session could not be encoded."
        case .decodeFailed:
            return "The saved Supabase session could not be decoded."
        case let .keychainFailed(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

@MainActor
protocol MonitoringSessionStorage {
    func load() throws -> StoredSupabaseSession?
    func save(_ session: StoredSupabaseSession) throws
    func clear() throws
}

struct SupabaseSessionStore: MonitoringSessionStorage {
    private let service = "monitor_helper.supabase.session"
    private let account = "authenticated-session"

    func load() throws -> StoredSupabaseSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SupabaseSessionStoreError.keychainFailed(status)
        }

        guard
            let data = item as? Data,
            let session = try? JSONDecoder().decode(StoredSupabaseSession.self, from: data)
        else {
            throw SupabaseSessionStoreError.decodeFailed
        }

        return session
    }

    func save(_ session: StoredSupabaseSession) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw SupabaseSessionStoreError.encodeFailed
        }

        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw SupabaseSessionStoreError.keychainFailed(updateStatus)
        }

        query.merge(attributes) { _, new in new }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SupabaseSessionStoreError.keychainFailed(addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SupabaseSessionStoreError.keychainFailed(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

extension StoredSupabaseSession {
    init(authSession: SupabaseAuthSession, receivedAt: Date = .now) {
        let expiresAt: Date?
        if let apiExpiresAt = authSession.expiresAt {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(apiExpiresAt))
        } else if let expiresIn = authSession.expiresIn {
            expiresAt = receivedAt.addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiresAt = nil
        }

        self.init(
            accessToken: authSession.accessToken,
            refreshToken: authSession.refreshToken,
            expiresAt: expiresAt,
            userID: authSession.user?.id,
            userEmail: authSession.user?.email
        )
    }
}
