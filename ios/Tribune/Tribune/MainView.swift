import AlertToast
internal import Builders
import SwiftData
import SwiftUI
import TextBuilder
import WebKit
import QuickLook
import BackgroundTasks

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var session: Session
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var searchText: String = ""
    @State private var presentedEpub: Newsletter?
    @State private var presentedSourceURL: URL?
    @State private var showSyncToast = false
    @State private var lastSyncStatus: SyncStatus?
    @State private var showDownloadToast = false
    @State private var lastDownloadError: String?
    @State private var showingSettings = false

    var body: some View {
        NewslettersList(
            searchText: searchText,
            openEpub: { n in openEpub(n) },
            openSource: { n in openSource(n) },
            deleteNewsletter: { n in delete(n) },
            toggleRead: { n in toggleRead(n) },
        )
        .navigationTitle("Newsletters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { settingsToolbar }
        .refreshable { await runLibrarySync() }
        .searchable(text: $searchText, prompt: "Search newsletters...")
        .fullScreenCover(item: $presentedEpub) { n in
            ReaderWebView(newsletter: n, library: Library(context: modelContext)) {
                presentedEpub = nil
            }
        }
        .quickLookPreview($presentedSourceURL)
        .sheet(isPresented: $showingSettings) { settingsSheet }
        .toast(
            isPresenting: $showSyncToast,
            alert: {
                makeSyncToast(for: lastSyncStatus)
            }
        )
        .toast(
            isPresenting: $showDownloadToast,
            alert: {
                makeDownloadToast(message: lastDownloadError)
            }
        )
        .onAppear { triggerBackgroundSync() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { triggerBackgroundSync() }
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings") { showingSettings = true }
        }
    }

    @ViewBuilder
    private var settingsSheet: some View {
        SettingsView()
            .onDisappear { triggerBackgroundSync() }
    }

    private func makeSyncToast(for status: SyncStatus?) -> AlertToast {
        switch status {
        case .blocked:
            return AlertToast(displayMode: .alert, type: .error(.red), title: "Sync blocked!")
        case .error(let msg):
            return AlertToast(
                displayMode: .alert, type: .error(.red), title: "Sync error", subTitle: msg)
        case .success:
            return AlertToast(
                displayMode: .banner(.slide), type: .complete(.green), title: "Sync success!")
        case .none:
            return AlertToast(displayMode: .alert, type: .error(.red), title: "Unknown error")
        }
    }

    private func makeDownloadToast(message: String?) -> AlertToast {
        AlertToast(
            displayMode: .alert, type: .error(.red),
            title: "Download error", subTitle: message ?? "")
    }
}

extension MainView {
    @MainActor
    func openEpub(_ n: Newsletter) {
        Task {
            if n.epubLastAccessedAt != nil {
                presentedEpub = n
                return
            }
            do {
                try await downloadManager.downloadEpub(newsletter: n)
                presentedEpub = n
            } catch {
                lastDownloadError = error.localizedDescription
                showDownloadToast = true
            }
        }
    }

    @MainActor
    func openSource(_ n: Newsletter) {
        Task {
            if n.sourceLastAccessedAt != nil {
                presentedSourceURL = Files.getFile(type: n.sourceFileType, id: n.id)
                return
            }
            do {
                try await downloadManager.downloadSource(newsletter: n)
                presentedSourceURL = Files.getFile(type: n.sourceFileType, id: n.id)
            } catch {
                lastDownloadError = error.localizedDescription
                showDownloadToast = true
            }
        }
    }

    @MainActor
    func triggerBackgroundSync() {
        Task { await doBackgroundSync() }
    }

    @MainActor
    func runLibrarySync() async {
        lastSyncStatus = await syncManager.syncLibrary()
        showSyncToast = true
    }

    private func doBackgroundSync() async {
        lastSyncStatus = await syncManager.syncLibrary()
        if let status = lastSyncStatus, case .success = status {
            showSyncToast = false
        } else {
            showSyncToast = true
        }
    }

    @MainActor
    func toggleRead(_ item: Newsletter) {
        if item.read {
            Task { try? await Library(context: modelContext).markNewsletterUnread(item) }
        } else {
            Task { try? await Library(context: modelContext).markNewsletterRead(item) }
        }
    }

    @MainActor
    func delete(_ item: Newsletter) {
        if !item.deleted {
            Task { try? await Library(context: modelContext).markNewsletterDeleted(item) }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Newsletter.self, configurations: config)
    for i in 0..<100 {
        let newsletter = Newsletter(
            id: i, title: "title\(i)", author: "author\(i)", sourceMimeType: "text/html",
            read: false, deleted: false, progress: "", createdAt: Date(), updatedAt: "",
            epubUpdatedAt: "")
        container.mainContext.insert(newsletter)
    }
    let session = Session()
    return NavigationStack {
        MainView().environmentObject(session)
    }
    .modelContainer(container)
}
