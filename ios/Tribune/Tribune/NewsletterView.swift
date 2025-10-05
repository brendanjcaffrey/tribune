import SwiftData
import SwiftUI

struct NewsletterView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var session: Session

    @Query(
        filter: NewsletterView.notDeleted,
        sort: NewsletterView.sortBy,
        animation: .default
    ) private var newsletters: [Newsletter]

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
        let newsletter = Newsletter(id: i, title: "title\(i)", author: "author\(i)", sourceMimeType: "text/html")
        container.mainContext.insert(newsletter)
    }
    return NavigationStack {
        NewsletterView()
    }
    .modelContainer(container)
}
