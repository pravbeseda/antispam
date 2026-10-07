import AntispamCore
import Foundation

/// Settings shared by the app and the Mail extension through their App Group.
struct SharedSettings {
    private static let thresholdKey = "threshold"
    // Not in the keychain: Mail fetches while the screen is locked, when keychain items are unavailable,
    // and keychain sharing needs a provisioning profile that expires every 7 days under a Personal Team.
    private static let apiKeyKey = "jevAPIKey"
    private static let extensionVersionKey = "extensionVersion"
    private static let extensionCheckDateKey = "extensionCheckDate"

    let decisionLogURL: URL
    private let defaults: UserDefaults

    init?(bundle: Bundle = .main) {
        guard let groupID = bundle.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let defaults = UserDefaults(suiteName: groupID),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        decisionLogURL = container.appending(path: "decisions.json")
        self.defaults = defaults
    }

    var threshold: Double {
        get { defaults.object(forKey: Self.thresholdKey) as? Double ?? SpamPolicy.defaultThreshold }
        nonmutating set { defaults.set(newValue, forKey: Self.thresholdKey) }
    }

    var apiKey: String? {
        get { defaults.string(forKey: Self.apiKeyKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.apiKeyKey) }
    }

    /// The extension version Mail last ran: Mail keeps the old extension loaded after a reinstall until it is reopened.
    var extensionCheck: (version: String, date: Date)? {
        get {
            guard let version = defaults.string(forKey: Self.extensionVersionKey),
                  let date = defaults.object(forKey: Self.extensionCheckDateKey) as? Date
            else { return nil }
            return (version, date)
        }
        nonmutating set {
            defaults.set(newValue?.version, forKey: Self.extensionVersionKey)
            defaults.set(newValue?.date, forKey: Self.extensionCheckDateKey)
        }
    }
}
