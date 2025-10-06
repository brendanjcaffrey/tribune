import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var session: Session
    @EnvironmentObject private var syncManager: SyncManager
    @State private var isDownloadModeOn: Bool = Defaults.getDownloadMode()
    @State private var isWiping = false
    @State private var wipeError: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                Toggle(isOn: $isDownloadModeOn) {
                    Text("Download Mode")
                        .font(.headline)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: isDownloadModeOn) {
                    Defaults.setDownloadMode(isDownloadModeOn)
                }

                Button(role: .destructive) {
                    Task { await handleLogout() }
                } label: {
                    Text(isWiping ? "Logging Out…" : "Log Out")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(isWiping)

                if let wipeError {
                    Text(wipeError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @MainActor
    private func handleLogout() async {
        isWiping = true
        wipeError = nil
        do {
            try wipeAllData()
            try modelContext.save()
            Defaults.clear()
            session.signOut()
        } catch {
            wipeError = "Failed to clear local data: \(error.localizedDescription)"
        }
        isWiping = false
    }

    @MainActor
    private func wipeAllData() throws {
        try deleteAll(of: Newsletter.self)
    }

    @MainActor
    private func deleteAll<T: PersistentModel>(of type: T.Type) throws {
        let descriptor = FetchDescriptor<T>() // fetch all
        let objects = try modelContext.fetch(descriptor)
        for object in objects {
            modelContext.delete(object)
        }
    }
}

#Preview {
    SettingsView()
}
