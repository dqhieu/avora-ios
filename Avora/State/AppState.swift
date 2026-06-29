import Foundation
import Supabase

@MainActor
@Observable
final class AppState {
    // Seeded synchronously from the locally persisted session so the first
    // frame already shows the right screen — no waiting on bootstrap().
    var isAuthenticated = SupabaseClientProvider.client.auth.currentSession != nil
    var profile: Profile?
    // Cached for the session so screens that need styles (grid, creation detail)
    // share one fetch. Pull-to-refresh on the grid passes force: true.
    var styles: [Style] = []
    // Credit economics fetched from the backend; seeded with fallback defaults
    // so the first frame and offline sessions still work.
    var config: CreditConfig = .fallback

    var userEmail: String? {
        SupabaseClientProvider.client.auth.currentUser?.email
    }

    func bootstrap() async {
        let session = try? await SupabaseClientProvider.client.auth.session
        if session != nil {
            isAuthenticated = true
            await configureRevenueCat()
            await refreshProfile()
            await loadConfig()
        } else if SupabaseClientProvider.client.auth.currentSession == nil {
            // No persisted session at all → definitely logged out. A failed
            // refresh with a cached session (e.g. offline) stays optimistic.
            isAuthenticated = false
        }
    }

    func refreshProfile() async {
        profile = try? await AvoraAPI.shared.fetchProfile()
    }

    func loadConfig() async {
        if let fetched = try? await AvoraAPI.shared.fetchCreditConfig() {
            config = fetched
        }
    }

    /// Number of generations buyable with `credits`, using the live config cost.
    func generations(for credits: Int) -> Int {
        credits / config.generationCost
    }

    func loadStyles(force: Bool = false) async throws {
        if !force, !styles.isEmpty { return }
        styles = try await AvoraAPI.shared.fetchStyles()
    }

    func style(id: String) -> Style? {
        styles.first { $0.id == id }
    }

    func configureRevenueCat() async {
        guard let session = try? await SupabaseClientProvider.client.auth.session else { return }
        AvoraPurchases.configure(appUserID: session.user.id.uuidString)
    }

    func signOut() async {
        try? await SupabaseClientProvider.client.auth.signOut()
        isAuthenticated = false
        profile = nil
    }
}
