import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var showWelcome: Bool {
        app.isAuthenticated && !hasSeenWelcome
    }

    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .font(.avoraBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(
            get: { showWelcome },
            set: { if !$0 { hasSeenWelcome = true } }
        )) {
            WelcomeView { hasSeenWelcome = true }
                .environment(app)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
