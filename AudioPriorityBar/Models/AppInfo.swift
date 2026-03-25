import Foundation

/// Utility struct to access app version and build information
struct AppInfo {
    /// The short version string (e.g., "1.0.0")
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// The build number (e.g., "42")
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Combined version and build string (e.g., "Version 1.0.0 (42)")
    static var versionString: String {
        "Version \(version) (\(build))"
    }

    /// App name from bundle
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Audio Priority Bar"
    }
}
