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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
