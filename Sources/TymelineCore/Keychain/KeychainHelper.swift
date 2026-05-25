import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Equatable {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .invalidData:
            return "Keychain item data is not valid UTF-8"
        }
    }
}

public enum KeychainHelper {
    public static let service = "app.tymeline"

    public enum ServiceKind: String {
        case linear
        case clockify
    }

    public static func accountName(service kind: ServiceKind, workspaceId: String) -> String {
        "\(kind.rawValue)-\(workspaceId)"
    }

    public static func setSecret(
        _ secret: String,
        for account: String,
        in service: String = KeychainHelper.service
    ) throws {
        guard let data = secret.data(using: .utf8) else { throw KeychainError.invalidData }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public static func getSecret(
        for account: String,
        in service: String = KeychainHelper.service
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let string = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func deleteSecret(
        for account: String,
        in service: String = KeychainHelper.service
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes ALL keychain items for the given service. Use in test teardown
    /// or when a user wipes a workspace. Be careful with the default service.
    ///
    /// `SecItemDelete` by default deletes only the first match, so we enumerate
    /// every account for the service and delete them individually.
    public static func deleteAll(in service: String) throws {
        let findQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]

        var items: CFTypeRef?
        let findStatus = SecItemCopyMatching(findQuery as CFDictionary, &items)

        switch findStatus {
        case errSecSuccess:
            guard let array = items as? [[String: Any]] else { return }
            for attrs in array {
                guard let account = attrs[kSecAttrAccount as String] as? String else { continue }
                try deleteSecret(for: account, in: service)
            }
        case errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(findStatus)
        }
    }
}
