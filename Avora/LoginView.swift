import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("LoginBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack {
                Spacer()
                loginButton
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }

    private var loginButton: some View {
        AvoraPrimaryButton(action: logIn) {
            loginButtonLabel
        }
        .disabled(isLoading)
    }

    @ViewBuilder
    private var loginButtonLabel: some View {
        if isLoading {
            ProgressView()
                .tint(Color.avoraOnAccent)
        } else {
            Label("Sign in with Apple", systemImage: "apple.logo")
        }
    }

    private func logIn() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await AuthService.signInWithApple(presentationAnchor: window)
                await app.configureRevenueCat()
                await app.refreshProfile()
                app.isAuthenticated = true
            } catch {
                // User cancelled or auth failed — stay on login screen
            }
        }
    }
}
