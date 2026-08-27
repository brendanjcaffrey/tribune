/// the download preferences the user set in settings, as the download manager
/// sees them
@MainActor
protocol DownloadSettings {
    var downloadMode: Bool { get }
    var downloadOnCellular: Bool { get }
}

struct UserDownloadSettings: DownloadSettings {
    // see SystemFileStore for why this isn't the implicit init
    nonisolated init() {}

    var downloadMode: Bool { Defaults.getDownloadMode() }
    var downloadOnCellular: Bool { Defaults.getDownloadOnCellular() }
}
