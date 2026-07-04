import SwiftUI
import GoogleSignIn
import RevenueCat

@main
struct AvoraApp: App {
    @State private var app: AppState

    init() {
        Purchases.configure(withAPIKey: "appl_ntflcZHcYyfOpVEQVePRhQzBXQC")
        FontRegistrar.registerBundledFonts()
        AppearanceConfigurator.configureNavigationBar()
        #if DEBUG
        let missingFonts = FontAudit.missingPostScriptNames()
        assert(missingFonts.isEmpty, "Missing bundled fonts: \(missingFonts)")
        #endif
        let app = AppState()
        _app = State(initialValue: app)
        Task { await app.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
