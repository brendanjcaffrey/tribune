import SwiftUI
import SwiftData

@main
struct TribuneApp: App {
    private let sharedModelContainer: ModelContainer

    @StateObject private var session: Session
    @StateObject private var syncManager: SyncManager

    init() {
        let schema = Schema([Newsletter.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.sharedModelContainer = container

            let library = Library(context: container.mainContext)
            let downloadManager = DownloadManager()

            _session = StateObject(wrappedValue: Session())
            _syncManager = StateObject(wrappedValue: SyncManager(library: library, downloadManager: downloadManager))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(syncManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

