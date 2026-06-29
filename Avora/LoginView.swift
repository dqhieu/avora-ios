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
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var loginButton: some View {
        Button(action: logIn) {
            loginButtonLabel
        }
        .buttonStyle(AvoraPrimaryButtonStyle())
        .disabled(isLoading)
    }

    private var loginButtonLabel: some View {
        Group {
            if isLoading {
                ProgressView().tint(Color.avoraOnAccent)
            } else {
                Text("Sign in with Apple")
            }
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
