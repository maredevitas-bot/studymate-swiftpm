import Foundation
import Security

protocol APIKeyProvider {
    func loadAPIKey() -> String?
    @discardableResult func save(apiKey: String) -> Bool
    func deleteAPIKey()
    func loadGeminiKey() -> String?
    @discardableResult func saveGeminiKey(_ key: String) -> Bool
    func deleteGeminiKey()
}

final class KeychainProvider: APIKeyProvider {
    private let service = "com.studymate.claude-api-key"
    private let geminiService = "com.studymate.gemini-api-key"
    private let account = "api-key"

    func loadAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(apiKey: String) -> Bool {
        deleteAPIKey()
        let data = Data(apiKey.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked  // explicit access policy
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func deleteAPIKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func loadGeminiKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: geminiService,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveGeminiKey(_ key: String) -> Bool {
        deleteGeminiKey()
        let data = Data(key.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: geminiService,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func deleteGeminiKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: geminiService,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
