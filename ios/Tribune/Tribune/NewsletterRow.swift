internal import Builders
import SwiftUI
import TextBuilder

struct NewsletterRow: View {
    @EnvironmentObject private var downloadManager: DownloadManager

    let n: Newsletter
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleRead: () -> Void
    let onContextMenu: () -> Void

    var body: some View {
        Button(action: onTap) {
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
            .contentShape(Rectangle())  // ensures the whole row is swipeable
            .opacity(n.read ? 0.6 : 1)
        }
        .simultaneousGesture(LongPressGesture()
            .onEnded { _ in
                onContextMenu()
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggleRead) {
                Label(
                    n.read ? "Mark Unread" : "Mark Read",
                    systemImage: n.read ? "envelope.badge.fill" : "envelope.open")
            }
            .tint(.blue)
        }
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
}
