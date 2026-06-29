import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .task { await app.bootstrap() }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
