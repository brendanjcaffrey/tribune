import Foundation

class Defaults {
    static let downloadModeKey = "downloadMode"
    static let downloadOnCellularKey = "downloadOnCellular"

    static func clear() {
        save(downloadModeKey, "false")
        save(downloadOnCellularKey, "false")
    }

    static func getDownloadMode() -> Bool {
        return load(downloadModeKey) == "true"
    }

    static func setDownloadMode(_ value: Bool) {
        save(downloadModeKey, value ? "true" : "false")
    }

    static func getDownloadOnCellular() -> Bool {
        return load(downloadOnCellularKey) == "true"
    }

    static func setDownloadOnCellular(_ value: Bool) {
        save(downloadOnCellularKey, value ? "true" : "false")
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
