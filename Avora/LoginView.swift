import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var loadingProvider: LoadingProvider?
    @State private var showAuthError = false

    private enum LoadingProvider { case apple, google }

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
        .alert("Couldn't sign in", isPresented: $showAuthError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong. Please try again.")
        }
    }

    private var loginButton: some View {
        AvoraPrimaryButton(action: logIn) {
            loginButtonLabel
        }
        .disabled(loadingProvider != nil)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var loginButtonLabel: some View {
        if loadingProvider == .apple {
            ProgressView()
                .tint(Color.avoraOnAccent)
        } else {
            Label("Continue with Apple", systemImage: "apple.logo")
        }
    }

    private var googleButton: some View {
        AvoraPrimaryButton(action: logInWithGoogle) {
            googleButtonLabel
        }
        .disabled(loadingProvider != nil)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var googleButtonLabel: some View {
        if loadingProvider == .google {
            ProgressView()
                .tint(Color.avoraOnAccent)
        } else {
            HStack(spacing: 8) {
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("Continue with Google")
            }
        }
    }

    private func logIn() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return }

        loadingProvider = .apple
        Task {
            defer { loadingProvider = nil }
            do {
                try await AuthService.signInWithApple(presentationAnchor: window)
                await completeSignIn()
            } catch {
                // Stay silent when the user cancels; surface real failures.
                if !AuthService.isCancellation(error) { showAuthError = true }
            }
        }
    }

    private func logInWithGoogle() {
        guard let root = rootViewController() else { return }
        loadingProvider = .google
        Task {
            defer { loadingProvider = nil }
            do {
                try await AuthService.signInWithGoogle(presenting: root)
                await completeSignIn()
            } catch {
                // Stay silent when the user cancels; surface real failures.
                if !AuthService.isCancellation(error) { showAuthError = true }
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
