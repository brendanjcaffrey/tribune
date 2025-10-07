import SwiftData
import SwiftUI
import AlertToast
import WebKit
import TextBuilder
internal import Builders

struct NewsletterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var session: Session
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var downloadManager: DownloadManager

    @Query(
        filter: NewsletterView.notDeleted,
        sort: NewsletterView.sortBy,
        animation: .default
    ) private var newsletters: [Newsletter]

    @State private var presentedEpub: Newsletter?
    @State private var showSyncToast = false
    @State private var lastSyncStatus: SyncStatus?
    @State private var showDownloadToast = false
    @State private var lastDownloadError: String?
    @State private var showingSettings = false

    var body: some View {
        List {
            ForEach(newsletters) { n in
                Button {
                    Task {
                        if n.epubLastAccessedAt != nil {
                            presentedEpub = n
                        } else {
                            do {
                                try await downloadManager.downloadEpub(newsletter: n)
                                presentedEpub = n
                            } catch {
                                lastDownloadError = error.localizedDescription
                                showDownloadToast = true
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(separator: " ") {
                            Text(n.title)
                            if n.epubLastAccessedAt != nil {
                                Text(Image(systemName: "book.closed"))
                            }
                            if n.sourceLastAccessedAt != nil {
                                Text(Image(systemName: "folder"))
                            }
                        }
                            .font(.headline)
                        Text(n.author)
                            .font(.subheadline)
                        HStack {
                            Text(Newsletter.displayFormatter.string(from: n.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if downloadManager.currentEpubDownloadId == n.id || downloadManager.currentSourceDownloadId == n.id {
                                ProgressView().controlSize( .small)
                            }
                        }
                    }
                    .contentShape(Rectangle()) // ensures the whole row is swipeable
                    .opacity(n.read ? 0.6 : 1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(n)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleRead(n)
                        } label: {
                            Label(n.read ? "Mark Unread" : "Mark Read",
                                  systemImage: n.read ? "envelope.badge.fill" : "envelope.open")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Newsletters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings") {
                    showingSettings = true
                }
            }
        }
        .refreshable() {
            lastSyncStatus = await syncManager.syncLibrary()
            showSyncToast = true
        }
        .sheet(item: $presentedEpub) { n in
            ReaderWebView(newsletter: n)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .onDisappear() {
                    Task { await doBackgroundSync() }
                }
        }
        .toast(isPresenting: $showSyncToast) {
            switch lastSyncStatus {
            case .blocked:
                return AlertToast(displayMode: .alert, type: .error(.red), title: "Sync blocked!")
            case .error(let msg):
                return AlertToast(displayMode: .alert, type: .error(.red), title: "Sync error", subTitle: msg)
            case .success:
                return AlertToast(displayMode: .banner(.slide), type: .complete(.green), title: "Sync success!")
            case .none:
                return AlertToast(displayMode: .alert, type: .error(.red), title: "Unknown error")
            }
        }
        .toast(isPresenting: $showDownloadToast) {
            return AlertToast(displayMode: .alert, type: .error(.red), title: "Download error", subTitle: lastDownloadError ?? "")
        }
        .onAppear() {
            Task { await doBackgroundSync() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await doBackgroundSync() }
            }
        }
    }

    private func doBackgroundSync() async {
        lastSyncStatus = await syncManager.syncLibrary()
        if let status = lastSyncStatus, case .success = status {
            showSyncToast = false
        } else {
            showSyncToast = true
        }
    }

    private func toggleRead(_ item: Newsletter) {
        item.read.toggle()
        try? modelContext.save()
    }

    private func delete(_ item: Newsletter) {
        if !item.deleted {
            item.deleted = true
            try? modelContext.save()
        }
    }
}

private extension NewsletterView {
    static let notDeleted: Predicate<Newsletter> = #Predicate { n in
        n.deleted == false
    }

    static let sortBy: [SortDescriptor<Newsletter>] = [
        .init(\.read, order: .forward),       // unread first
        .init(\.createdAt, order: .reverse),  // newest first
        .init(\.id, order: .forward)          // stable tiebreaker
    ]
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Newsletter.self, configurations: config)
    for i in 0..<100 {
        let newsletter = Newsletter(id: i, title: "title\(i)", author: "author\(i)", sourceMimeType: "text/html", read: false, deleted: false, progress: "", createdAt: Date(), updatedAt: "", epubUpdatedAt: "")
        container.mainContext.insert(newsletter)
    }
    let session = Session()
    return NavigationStack {
        NewsletterView().environmentObject(session)
    }
    .modelContainer(container)
}
