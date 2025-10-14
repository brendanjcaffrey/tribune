import Foundation
import SwiftData
import SwiftUI

struct NewslettersList: View {
    @Environment(\.modelContext) private var modelContext

    let searchText: String
    let openEpub: (_: Newsletter) -> Void
    let openSource: (_: Newsletter) -> Void
    let deleteNewsletter: (_: Newsletter) -> Void
    let toggleRead: (_: Newsletter) -> Void

    @Query private var newsletters: [Newsletter]

    init(
        searchText: String,
        openEpub: @escaping (_: Newsletter) -> Void,
        openSource: @escaping (_: Newsletter) -> Void,
        deleteNewsletter: @escaping (_: Newsletter) -> Void,
        toggleRead: @escaping (_: Newsletter) -> Void
    ) {
        self.searchText = searchText
        self.openEpub = openEpub
        self.openSource = openSource
        self.deleteNewsletter = deleteNewsletter
        self.toggleRead = toggleRead

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
                            openEpub: { openEpub(n) },
                            openSource: { openSource(n) },
                            deleteNewsletter: { deleteNewsletter(n) },
                            toggleRead: { toggleRead(n) },
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
