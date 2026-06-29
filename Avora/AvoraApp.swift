import SwiftUI

@main
struct AvoraApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
        }
    }
}
