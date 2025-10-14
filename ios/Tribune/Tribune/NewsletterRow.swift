internal import Builders
import SwiftUI
import TextBuilder

struct NewsletterRow: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var showContextMenu: Bool = false

    let n: Newsletter
    let openEpub: () -> Void
    let openSource: () -> Void
    let deleteNewsletter: () -> Void
    let toggleRead: () -> Void

    var body: some View {
        Button(action: openEpub) {
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                    .font(.headline)
                Text(n.author)
                    .font(.subheadline)
                HStack {
                    Text(Newsletter.displayFormatter.string(from: n.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if downloadManager.currentEpubDownloadId == n.id
                        || downloadManager.currentSourceDownloadId == n.id
                    {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(n.read ? 0.6 : 1)
        }
        .contentShape(Rectangle())  // ensures the whole row is swipeable
        .simultaneousGesture(LongPressGesture()
            .onEnded { _ in
                contextMenu()
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: deleteNewsletter) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleRead) {
                Label(
                    n.read ? "Mark Unread" : "Mark Read",
                    systemImage: n.read ? "envelope.badge.fill" : "envelope.open")
            }
            .tint(.blue)
        }
        .confirmationDialog(
            "Newsletter options",
            isPresented: $showContextMenu,
            titleVisibility: .hidden,
            actions: { contextMenuActions() },
        )
    }

    @ViewBuilder
    private var titleLine: some View {
        Text(separator: " ") {
            Text(n.title)
            if n.epubLastAccessedAt != nil {
                Text(Image(systemName: "book.closed"))
            }
            if n.sourceLastAccessedAt != nil {
                Text(Image(systemName: "folder"))
            }
        }
    }

    @ViewBuilder
    private func contextMenuActions() -> some View {
        Button("Mark as \(n.read ? "Unread" : "Read")", action: { toggleRead() })
        Button("Open ePub", action: { openEpub() })
        Button("Open Source", action: { openSource() })
        Button("Delete", role: .destructive, action: { deleteNewsletter() })
        Button("Cancel", role: .cancel) { }
    }

    @MainActor
    func contextMenu() {
        showContextMenu = true
    }
}
