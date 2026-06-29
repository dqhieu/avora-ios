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
        .font(.avoraBody)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
