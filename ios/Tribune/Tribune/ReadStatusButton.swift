import SwiftData
import SwiftUI

/// shows whether the open newsletter is read and lets it be flipped either way. the
/// reader marks it read on its own once the end of the document is reached, and the
/// newsletter is observable, so the icon follows along without any extra plumbing
struct ReadStatusButton: View {
    @Environment(\.modelContext) private var modelContext

    let n: Newsletter

    var body: some View {
        ReaderOverlayButton(systemName: n.read ? "envelope.open.fill" : "envelope") {
            toggle()
        }
        .accessibilityLabel(n.read ? "mark as unread" : "mark as read")
    }

    @MainActor
    private func toggle() {
        let library = Library(context: modelContext)
        if n.read {
            Task { try? await library.markNewsletterUnread(n) }
        } else {
            Task { try? await library.markNewsletterRead(n) }
        }
    }
}
