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
    @State private var isRestoring = false
    @State private var isSigningOut = false
    @State private var isDeleting = false
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
                Button {
                    Haptics.tap()
                    Task {
                        isRestoring = true
                        try? await AvoraPurchases.restore()
                        await app.refreshProfile()
                        isRestoring = false
                    }
                } label: {
                    actionLabel("Restore Purchases", loading: isRestoring)
                }
                .disabled(isRestoring)
                Button("Show Intro Again") {
                    Haptics.tap()
                    hasSeenWelcome = false
                    dismiss()
                }
                Button {
                    Haptics.tap()
                    Task {
                        isSigningOut = true
                        await app.signOut()
                        isSigningOut = false
                    }
                } label: {
                    actionLabel("Sign Out", loading: isSigningOut)
                }
                .disabled(isSigningOut)
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
                Button(role: .destructive) {
                    Haptics.warning()
                    confirmDelete = true
                } label: {
                    actionLabel("Delete Account", loading: isDeleting)
                }
                .disabled(isDeleting)
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
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task {
                    isDeleting = true
                    do {
                        try await AvoraAPI.shared.deleteAccount()
                        await app.signOut()
                    } catch {
                        Haptics.error()
                        deleteError = "Couldn't delete your account. Please try again."
                    }
                    isDeleting = false
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, loading: Bool) -> some View {
        HStack {
            Text(title)
            if loading {
                Spacer()
                ProgressView()
            }
        }
    }
}
