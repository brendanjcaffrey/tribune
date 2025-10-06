import Foundation

class Defaults {
    static let downloadModeKey = "downloadMode"

    static func clear() {
        save(downloadModeKey, "false")
    }

    static func getDownloadMode() -> Bool {
        return load(downloadModeKey) == "true"
    }

    static func setDownloadMode(_ value: Bool) {
        save(downloadModeKey, value ? "true" : "false")
    }

    private static func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }

    private static func load(_ key: String) -> String {
        if let value = UserDefaults.standard.object(forKey: key) as? String {
            return value
        } else {
            return ""
        }
    }
}
