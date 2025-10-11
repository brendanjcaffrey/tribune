import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct TribuneApp: App {
    private let sharedModelContainer: ModelContainer

    @Environment(\.scenePhase) private var phase
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

    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTasks.syncId)
        try? BGTaskScheduler.shared.submit(request)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(downloadManager)
                .environmentObject(syncManager)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background: scheduleAppRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BGTasks.syncId)) {
            switch await syncManager.syncLibrary(skipDownload: true) {
            case .success: break
            case .blocked: print("background sync blocked?")
            case .error(let e): print("background sync error: \(e)")
            }
        }
    }
}

