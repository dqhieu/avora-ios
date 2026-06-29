import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        List {
            if let email = app.userEmail {
                Section("Account") {
                    LabeledContent("Email", value: email)
                }
            }
            if let p = app.profile {
                Section("Credits") {
                    LabeledContent("Weekly", value: "\(p.weeklyCredits)")
                    LabeledContent("Extra", value: "\(p.extraCredits)")
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
        .toolbar(.hidden, for: .tabBar)
        .alert("Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .confirmationDialog(
            "Delete your account? This cannot be undone.",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    do {
                        try await AvoraAPI.shared.deleteAccount()
                        await app.signOut()
                    } catch {
                        deleteError = "Couldn't delete your account. Please try again."
                    }
                }
            }
        }
    }
}
