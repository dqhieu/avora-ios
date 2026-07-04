import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleteError: String?
    #if DEBUG
    @AppStorage(AvoraConfig.mockGenerationKey) private var mockGeneration = false
    #endif

    var body: some View {
        List {
            if let email = app.userEmail {
                Section("Account") {
                    LabeledContent("Email", value: email)
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
            #if DEBUG
            Section("Developer") {
                Toggle("Mock generation", isOn: $mockGeneration)
            }
            #endif
            Section {
                Button("Delete Account", role: .destructive) {
                    confirmDelete = true
                }
            } footer: {
                Text("Permanently deletes your account, images, and remaining credits.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
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
