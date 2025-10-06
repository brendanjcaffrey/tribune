import SwiftUI
import SwiftData

@main
struct TribuneApp: App {
    private let sharedModelContainer: ModelContainer

    @StateObject private var session: Session
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var syncManager: SyncManager

    init() {
        let schema = Schema([Newsletter.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.sharedModelContainer = container

            let library = Library(context: container.mainContext)
            let downloadManager = DownloadManager(library: library)
            let syncManager = SyncManager(library: library, downloadManager: downloadManager)

            _session = StateObject(wrappedValue: Session())
            _downloadManager = StateObject(wrappedValue: downloadManager)
            _syncManager = StateObject(wrappedValue: syncManager)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(downloadManager)
                .environmentObject(syncManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

