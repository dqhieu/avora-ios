import Foundation
import Supabase

@MainActor
@Observable
final class AppState {
    var isAuthenticated = false
    var profile: Profile?

    func bootstrap() async {
        let session = try? await SupabaseClientProvider.client.auth.session
        isAuthenticated = session != nil
        if isAuthenticated { await refreshProfile() }
    }

    func refreshProfile() async {
        profile = try? await AvoraAPI.shared.fetchProfile()
    }

    func signOut() async {
        try? await SupabaseClientProvider.client.auth.signOut()
        isAuthenticated = false
        profile = nil
    }
}
