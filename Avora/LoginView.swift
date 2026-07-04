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

            VStack(spacing: 12) {
                Spacer()
                loginButton
                googleButton
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
        .preferredColorScheme(.light)
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

    private var googleButton: some View {
        AvoraPrimaryButton(action: logInWithGoogle) {
            Label("Continue with Google", systemImage: "globe")
        }
        .disabled(isLoading)
        .preferredColorScheme(.light)
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
                await completeSignIn()
            } catch {
                // User cancelled or auth failed — stay on login screen
            }
        }
    }

    private func logInWithGoogle() {
        guard let root = rootViewController() else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await AuthService.signInWithGoogle(presenting: root)
                await completeSignIn()
            } catch {
                // User cancelled or auth failed — stay on login screen
            }
        }
    }

    private func completeSignIn() async {
        await app.configureRevenueCat()
        await app.refreshProfile()
        app.isAuthenticated = true
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }?
            .rootViewController
    }
}
