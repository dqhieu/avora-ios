import SwiftUI
#if DEBUG
import TipKit
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @State private var editingUsername = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    #if DEBUG
    @AppStorage(AvoraConfig.mockGenerationKey) private var mockGeneration = false
    #endif

    var body: some View {
        List {
            Section("Account") {
                if let username = app.profile?.username {
                    Button {
                        Haptics.tap()
                        editingUsername = true
                    } label: {
                        LabeledContent("Username", value: username)
                    }
                    .tint(.primary)
                }
                if let email = app.userEmail {
                    LabeledContent("Email", value: email)
                }
            }
            Section {
                Button("Restore Purchases") {
                    Haptics.tap()
                    Task {
                        try? await AvoraPurchases.restore()
                        await app.refreshProfile()
                    }
                }
                Button("Show Intro Again") {
                    Haptics.tap()
                    hasSeenWelcome = false
                    dismiss()
                }
                Button("Sign Out") {
                    Haptics.tap()
                    Task { await app.signOut() }
                }
            }
            #if DEBUG
            Section("Developer") {
                Toggle("Mock generation", isOn: $mockGeneration)
                    .onChange(of: mockGeneration) { Haptics.selection() }
                if #available(iOS 26.0, *) {
                    Button("Reset Select Photo tip") {
                        Haptics.tap()
                        Task { await SelectPhotoTip().resetEligibility() }
                    }
                }
            }
            #endif
            Section {
                Button("Delete Account", role: .destructive) {
                    Haptics.warning()
                    confirmDelete = true
                }
            } footer: {
                Text("Permanently deletes your account, images, and remaining credits.")
            }
        }
        .avoraSoftScrollEdge()
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Haptics.tap(); dismiss() }
            }
        }
        .sheet(isPresented: $editingUsername) {
            EditUsernameSheet(current: app.profile?.username ?? "")
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
                        Haptics.error()
                        deleteError = "Couldn't delete your account. Please try again."
                    }
                }
            }
        }
    }
}
