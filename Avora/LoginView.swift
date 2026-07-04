import SwiftUI
import VariableBlur

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var loadingProvider: LoadingProvider?
    @State private var showAuthError = false

    private enum LoadingProvider { case apple, google }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            InfiniteMosaicBackground()

            VStack(spacing: 12) {
                Spacer()
                VStack(spacing: 12) {
                    branding
                    loginButton
                    googleButton
                }
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 28)
                .background(bottomBackdrop)
            }
        }
        .alert("Couldn't sign in", isPresented: $showAuthError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong. Please try again.")
        }
    }

    private var bottomBackdrop: some View {
        ZStack {
            VariableBlurView(maxBlurRadius: 4, direction: .blurredBottomClearTop)
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var branding: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avora")
                .font(.avoraHero)
            Text("Your photos, reimagined.")
                .font(.avoraCallout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .padding(.bottom, 20)
        .padding(.top, 32)
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
