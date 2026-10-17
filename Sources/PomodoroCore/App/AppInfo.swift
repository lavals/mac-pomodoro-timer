import Foundation

/// Static information about the running app.
public enum AppInfo {
    /// Marketing version from the bundle's `CFBundleShortVersionString`,
    /// or `"dev"` when running unbundled (e.g. `swift run`, tests).
    public static var version: String {
        version(from: Bundle.main.infoDictionary)
    }

    /// Resolves the version from an `Info.plist` dictionary; empty or missing values fall back to `"dev"`.
    static func version(from infoDictionary: [String: Any]?) -> String {
        guard let value = infoDictionary?["CFBundleShortVersionString"] as? String,
              !value.isEmpty
        else { return "dev" }
        return value
    }
}
