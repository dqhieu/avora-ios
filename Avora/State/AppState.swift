import Foundation
import Supabase

@MainActor
@Observable
final class AppState {
    // Seeded synchronously from the locally persisted session so the first
    // frame already shows the right screen — no waiting on bootstrap().
    var isAuthenticated = SupabaseClientProvider.client.auth.currentSession != nil
    var profile: Profile?
    // Seeded synchronously from the last on-disk snapshot so the styles grid's
    // first frame already has data; refreshed once per session on first view.
    // Screens that need styles (grid, creation detail) share that fetch.
    var styles: [Style] = SnapshotStore.loadStyles() ?? []
    private var didFetchStyles = false
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

    /// Marks the signup bonus seen and optimistically clears the flag locally so
    /// the modal dismisses immediately. If the RPC failed, the next profile fetch
    /// re-shows the modal (at-least-once display) rather than losing it silently.
    func markSignupBonusSeen() async {
        try? await AvoraAPI.shared.markSignupBonusSeen()
        profile?.signupBonusSeen = true
    }

    /// Changes the username via the authoritative RPC. On success, updates the
    /// local profile so Settings reflects the new name without a refetch.
    func updateUsername(_ newUsername: String) async -> AvoraAPI.SetUsernameResult {
        let result = (try? await AvoraAPI.shared.setUsername(newUsername)) ?? .invalid
        if result == .ok {
            profile?.username = newUsername
        }
        return result
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
        if !force, didFetchStyles { return }
        styles = try await AvoraAPI.shared.fetchStyles()
        didFetchStyles = true
        SnapshotStore.saveStyles(styles)
    }

    func style(id: String) -> Style? {
        styles.first { $0.id == id }
    }

    // Logs the signed-in Supabase user into RevenueCat (the SDK is configured
    // anonymously at launch). Called at bootstrap for an existing session and
    // from the login flow after a fresh sign-in.
    func configureRevenueCat() async {
        guard let session = try? await SupabaseClientProvider.client.auth.session else { return }
        await AvoraPurchases.logIn(appUserID: session.user.id.uuidString)
    }

    func signOut() async {
        await AvoraPurchases.logOut()
        try? await SupabaseClientProvider.client.auth.signOut()
        isAuthenticated = false
        profile = nil
        SnapshotStore.clearCollection()
        SnapshotStore.clearCommunity()
    }
}
