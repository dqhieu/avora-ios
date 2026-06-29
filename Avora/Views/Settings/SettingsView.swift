import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let p = app.profile {
                Section("Credits") {
                    LabeledContent("Weekly", value: "\(p.weeklyCredits)")
                    LabeledContent("Extra", value: "\(p.extraCredits)")
                    LabeledContent("Generations left", value: "\(p.totalGenerations)")
                }
            }
            Section {
                Button("Restore Purchases") {
                    Task {
                        try? await AvoraPurchases.restore()
                        await app.refreshProfile()
                    }
                }
                Button("Sign Out") {
                    Task { await app.signOut() }
                }
            }
            Section {
                Button("Delete Account", role: .destructive) {
                    confirmDelete = true
                }
            } footer: {
                Text("Permanently deletes your account, images, and remaining credits.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete your account? This cannot be undone.",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    try? await AvoraAPI.shared.deleteAccount()
                    await app.signOut()
                }
            }
        }
    }
}
