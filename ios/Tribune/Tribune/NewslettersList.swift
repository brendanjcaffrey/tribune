import Foundation
import SwiftData
import SwiftUI

struct NewslettersList: View {
    @Environment(\.modelContext) private var modelContext

    let searchText: String
    let onTap: (_: Newsletter) -> Void
    let onDelete: (_: Newsletter) -> Void
    let onToggleRead: (_: Newsletter) -> Void
    let onContextMenu: (_: Newsletter) -> Void

    @Query private var newsletters: [Newsletter]

    init(
        searchText: String,
        onTap: @escaping (_: Newsletter) -> Void,
        onDelete: @escaping (_: Newsletter) -> Void,
        onToggleRead: @escaping (_: Newsletter) -> Void,
        onContextMenu: @escaping (_: Newsletter) -> Void,
    ) {
        self.searchText = searchText
        self.onTap = onTap
        self.onDelete = onDelete
        self.onToggleRead = onToggleRead
        self.onContextMenu = onContextMenu

        let predicate = #Predicate<Newsletter> { n in
            if n.deleted {
                return false
            } else if searchText.isEmpty {
                return true
            } else {
                return n.title.localizedStandardContains(searchText)
                    || n.author.localizedStandardContains(searchText)
            }
        }

        _newsletters = Query(
            filter: predicate,
            sort: Self.sortBy,
        )
    }

    var body: some View {
        Group {
            if newsletters.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No newsletters match '\(searchText)'")
                )
            } else if newsletters.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "No Newsletters",
                    systemImage: "tray",
                    description: Text("Go add some!")
                )
            } else {
                List {
                    ForEach(newsletters) { n in
                        NewsletterRow(
                            n: n,
                            onTap: { onTap(n) },
                            onDelete: { onDelete(n) },
                            onToggleRead: { onToggleRead(n) },
                            onContextMenu: { onContextMenu(n) },
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    static let sortBy: [SortDescriptor<Newsletter>] = [
        .init(\.read, order: .forward),  // unread first
        .init(\.createdAt, order: .reverse),  // newest first
        .init(\.id, order: .forward),  // stable tiebreaker
    ]
}
