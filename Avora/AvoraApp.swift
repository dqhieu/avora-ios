import SwiftUI

@main
struct AvoraApp: App {
    @State private var app: AppState

    init() {
        let app = AppState()
        _app = State(initialValue: app)
        Task { await app.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
        }
    }
}
