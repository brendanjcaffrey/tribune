import Foundation

/// the on disk store for downloaded newsletter files. the app uses `Files`,
/// tests substitute their own so nothing touches the filesystem
@MainActor
protocol FileStoring {
    func fileExists(type: FileType, id: Int) -> Bool
    @discardableResult func writeFile(type: FileType, id: Int, data: Data) -> Bool
    func deleteFile(type: FileType, id: Int)
}

struct SystemFileStore: FileStoring {
    // the protocol is main actor isolated, so the implicit init would be too,
    // which the default argument in DownloadManager's init can't call
    nonisolated init() {}

    func fileExists(type: FileType, id: Int) -> Bool {
        Files.fileExists(type: type, id: id)
    }

    @discardableResult
    func writeFile(type: FileType, id: Int, data: Data) -> Bool {
        Files.writeFile(type: type, id: id, data: data)
    }

    func deleteFile(type: FileType, id: Int) {
        Files.deleteFile(type: type, id: id)
    }
}
