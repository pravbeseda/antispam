import Foundation

extension Bundle {
    /// The release version that scripts/install.sh builds in, e.g. 0.1.3.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
