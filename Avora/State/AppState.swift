import Foundation
import Supabase

@MainActor
@Observable
final class AppState {
    // Seeded synchronously from the locally persisted session so the first
    // frame already shows the right screen — no waiting on bootstrap().
    var isAuthenticated = SupabaseClientProvider.client.auth.currentSession != nil
    var profile: Profile?

    var userEmail: String? {
        SupabaseClientProvider.client.auth.currentUser?.email
    }

    func bootstrap() async {
        let session = try? await SupabaseClientProvider.client.auth.session
        if session != nil {
            isAuthenticated = true
            await configureRevenueCat()
            await refreshProfile()
        } else if SupabaseClientProvider.client.auth.currentSession == nil {
            // No persisted session at all → definitely logged out. A failed
            // refresh with a cached session (e.g. offline) stays optimistic.
            isAuthenticated = false
        }
    }

    func refreshProfile() async {
        profile = try? await AvoraAPI.shared.fetchProfile()
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
