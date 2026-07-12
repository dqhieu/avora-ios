import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var showWelcome: Bool {
        app.isAuthenticated && !hasSeenWelcome
    }

    private var showSignupBonus: Bool {
        hasSeenWelcome
            && app.profile?.signupBonusSeen == false
            && app.config.signupExtra > 0
    }

    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
                    .overlay {
                        if showSignupBonus {
                            SignupBonusModal(credits: app.config.signupExtra) {
                                Task { await app.markSignupBonusSeen() }
                            }
                            .transition(.opacity)
                        }
                    }
            } else {
                LoginView()
            }
        }
        .font(.avoraBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: showSignupBonus)
        .fullScreenCover(isPresented: Binding(
            get: { showWelcome },
            set: { if !$0 { hasSeenWelcome = true } }
        )) {
            WelcomeView { hasSeenWelcome = true }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
