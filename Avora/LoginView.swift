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

    @ViewBuilder
    private var loginButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: logIn) {
                loginButtonLabel
            }
            .buttonStyle(.glassProminent)
            .tint(Color.clear)
            .disabled(isLoading)
        } else {
            Button(action: logIn) {
                loginButtonLabel
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
            .disabled(isLoading)
        }
    }

    private var loginButtonLabel: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                Text("Sign in with Apple")
                    .foregroundStyle(.black)
                    .font(.avoraButton)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(.capsule)
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
