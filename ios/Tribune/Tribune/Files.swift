import Foundation
import UIKit

enum FileType: String {
    case epub
    case source
}

class Files {
    static func getDirectory(type: FileType) -> URL {
        return URL.documentsDirectory.appending(path: type.rawValue)
    }

    static func ensureDirectoryExists(directory: URL) {
        do {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Self.excludeFromBackup(url: directory)
            }
        } catch {
            print("unable to create \(directory.path): \(error)")
            abort()
        }
    }

    static func deleteDirectory(type: FileType) {
        let directory = getDirectory(type: type)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            print("unable to delete \(directory.path): \(error)")
            abort()
        }
    }

    static func getFile(type: FileType, id: Int) -> URL {
        let directory = getDirectory(type: type)
        return directory.appendingPathComponent(String(id))
    }

    static func fileExists(type: FileType, id: Int) -> Bool {
        let file = getFile(type: type, id: id)
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func deleteFile(type: FileType, id: Int) {
        let file = getFile(type: type, id: id)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("unable to delete \(file.path): \(error)")
            abort()
        }
    }

    @discardableResult
    static func writeFile(type: FileType, id: Int, data: Data) -> Bool {
        let file = getFile(type: type, id: id)
        do {
            ensureDirectoryExists(directory: file.deletingLastPathComponent())
            deleteFile(type: type, id: id)
            try data.write(to: file, options: .atomic)
            try Self.excludeFromBackup(url: file)
            return true
        } catch {
            print("unable to write \(file.path): \(error)")
            return false
        }
    }

    static func excludeFromBackup(url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var modifiableURL = url
        try modifiableURL.setResourceValues(resourceValues)
    }
}
