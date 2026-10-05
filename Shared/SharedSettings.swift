import AntispamCore
import Foundation
import Security

/// Settings shared by the app and the Mail extension through their App Group.
struct SharedSettings {
    private static let thresholdKey = "threshold"
    private static let apiKeyAccount = "jev-api-key"

    let decisionLogURL: URL
    private let groupID: String
    private let defaults: UserDefaults

    init?(bundle: Bundle = .main) {
        guard let groupID = bundle.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let defaults = UserDefaults(suiteName: groupID),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        decisionLogURL = container.appending(path: "decisions.json")
        self.groupID = groupID
        self.defaults = defaults
    }

    var threshold: Double {
        get { defaults.object(forKey: Self.thresholdKey) as? Double ?? SpamPolicy.defaultThreshold }
        nonmutating set { defaults.set(newValue, forKey: Self.thresholdKey) }
    }

    func apiKey() -> String? {
        var query = keychainQuery
        query[kSecReturnData] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setAPIKey(_ key: String) throws {
        SecItemDelete(keychainQuery as CFDictionary)
        var item = keychainQuery
        item[kSecValueData] = Data(key.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    // The keychain access group has the same ID as the App Group (see `keychain-access-groups` in project.yml).
    private var keychainQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: groupID,
            kSecAttrAccount: Self.apiKeyAccount,
            kSecAttrAccessGroup: groupID,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}

struct KeychainError: Error {
    let status: OSStatus
}
