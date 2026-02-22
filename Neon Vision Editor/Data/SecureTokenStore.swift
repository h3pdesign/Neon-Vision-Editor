import Foundation
import Security

///MARK: - Token Keys
// Logical API-token keys mapped to Keychain account names.
enum APITokenKey: String, CaseIterable {
    case grok
    case openAI
    case gemini
    case anthropic

    var account: String {
        switch self {
        case .grok: return "GrokAPIToken"
        case .openAI: return "OpenAIAPIToken"
        case .gemini: return "GeminiAPIToken"
        case .anthropic: return "AnthropicAPIToken"
        }
    }
}

///MARK: - Secure Token Store
// Keychain-backed storage for provider API tokens.
enum SecureTokenStore {
    private static let service = "h3p.Neon-Vision-Editor.tokens"
    private static let debugTokenPrefix = "DebugTokenStore."

    // Returns UTF-8 token value or empty string when token is missing.
    static func token(for key: APITokenKey) -> String {
#if DEBUG
        let debugValue = UserDefaults.standard.string(forKey: debugTokenPrefix + key.account) ?? ""
        return debugValue.trimmingCharacters(in: .whitespacesAndNewlines)
#else
        guard let data = readData(for: key),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
#endif
    }

    @discardableResult
    // Writes token to Keychain or deletes entry when value is empty.
    static func setToken(_ value: String, for key: APITokenKey) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
#if DEBUG
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: debugTokenPrefix + key.account)
            return true
        }
        UserDefaults.standard.set(trimmed, forKey: debugTokenPrefix + key.account)
        return true
#else
        if trimmed.isEmpty {
            return deleteToken(for: key)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let baseQuery = baseQuery(for: key)

        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            // Keep secrets device-bound and unavailable while the device is locked.
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return true
            }
            logKeychainError(status: addStatus, context: "add token \(key.account)")
            return false
        }

        logKeychainError(status: updateStatus, context: "update token \(key.account)")
        return false
#endif
    }

    // Migrates legacy UserDefaults tokens into Keychain and cleans stale defaults.
    static func migrateLegacyUserDefaultsTokens() {
        for key in APITokenKey.allCases {
            let defaultsKey = key.account
            let defaultsValue = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
            let trimmedDefaultsValue = defaultsValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasStoredValue = !token(for: key).isEmpty

            if !hasStoredValue && !trimmedDefaultsValue.isEmpty {
                let didStore = setToken(trimmedDefaultsValue, for: key)
                if didStore {
                    UserDefaults.standard.removeObject(forKey: defaultsKey)
                }
                continue
            }

            if hasStoredValue || trimmedDefaultsValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    private static func readData(for key: APITokenKey) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || isMissingDataStoreStatus(status) {
            // Some environments report missing keychain backends with legacy CSSM errors.
            // Treat them as "token not present" to keep app startup resilient.
            return nil
        }
        guard status == errSecSuccess else {
            logKeychainError(status: status, context: "read token \(key.account)")
            return nil
        }
        guard let data = item as? Data else {
            logKeychainError(status: errSecInternalError, context: "read token \(key.account) returned non-data payload")
            return nil
        }
        return data
    }

    @discardableResult
    // Deletes a token entry from Keychain.
    private static func deleteToken(for key: APITokenKey) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }
        logKeychainError(status: status, context: "delete token \(key.account)")
        return false
    }

    // Builds a strongly-typed keychain query to avoid CF bridging issues at runtime.
    private static func baseQuery(for key: APITokenKey) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.account
        ]
    }

    // Maps legacy CSSM keychain "store missing" errors to a benign "not found" condition.
    private static func isMissingDataStoreStatus(_ status: OSStatus) -> Bool {
        status == errSecNoSuchKeychain || status == errSecNotAvailable || status == errSecInteractionNotAllowed || status == -2147413737
    }

    // Emits consistent Keychain error diagnostics for support/debugging.
    private static func logKeychainError(status: OSStatus, context: String) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus"
        NSLog("SecureTokenStore error (\(context)): \(status) - \(message)")
    }
}
