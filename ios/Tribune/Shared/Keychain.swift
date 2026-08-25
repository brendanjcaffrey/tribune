import Foundation

enum Keychain {
    static func storeJWT(_ jwt: String, service: String, account: String, accessGroup: String? = nil) throws {
        try? deleteJWT(service: service, account: account, accessGroup: accessGroup)

        let data = Data(jwt.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        applyAccessGroup(accessGroup, to: &query)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    static func readJWT(service: String, account: String, accessGroup: String? = nil) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        applyAccessGroup(accessGroup, to: &query)
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return String(data: data, encoding: .utf8)
    }

    static func deleteJWT(service: String, account: String, accessGroup: String? = nil) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        applyAccessGroup(accessGroup, to: &query)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    // an unsigned build has no team prefix to build a group out of, and passing
    // an empty one is an error rather than a no-op, so leave the key off and let
    // the item land in the caller's default group
    private static func applyAccessGroup(_ accessGroup: String?, to query: inout [String: Any]) {
        guard let accessGroup, !accessGroup.isEmpty else { return }
        query[kSecAttrAccessGroup as String] = accessGroup
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error \(status)"])
    }
}
