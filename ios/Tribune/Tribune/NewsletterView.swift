import SwiftData
import SwiftUI
import AlertToast

struct NewsletterView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var session: Session
    @EnvironmentObject private var syncManager: SyncManager

    @Query(
        filter: NewsletterView.notDeleted,
        sort: NewsletterView.sortBy,
        animation: .default
    ) private var newsletters: [Newsletter]

    @State private var showToast = false
    @State private var lastSyncStatus: SyncStatus?

    var body: some View {
        List {
            ForEach(newsletters) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title)
                        .font(.headline)
                    Text(n.author)
                        .font(.subheadline)
                    Text(Newsletter.displayFormatter.string(from: n.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .listStyle(.inset)
        .navigationTitle("Newsletters")
        .refreshable() {
            lastSyncStatus = await syncManager.syncLibrary()
            showToast = true
        }
        .toast(isPresenting: $showToast){
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
        .onAppear() {
            Task {
                lastSyncStatus = await syncManager.syncLibrary()
                if let status = lastSyncStatus, case .success = status {
                    showToast = false
                } else {
                    showToast = true
                }
            }
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
