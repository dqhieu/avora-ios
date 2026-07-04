import Foundation
import RevenueCat

enum AvoraPurchases {
    /// Identify the RevenueCat user as the signed-in Supabase user. The SDK is
    /// configured once (anonymously) at launch in AvoraApp; this aliases that
    /// anonymous id to the real user id, so purchases — and the webhook's
    /// `app_user_id` — tie to the correct account.
    static func logIn(appUserID: String) async {
        _ = try? await Purchases.shared.logIn(appUserID)
    }

    /// Revert to a fresh anonymous id on sign-out, so the next account on this
    /// device doesn't inherit the previous user's RevenueCat identity.
    static func logOut() async {
        _ = try? await Purchases.shared.logOut()
    }

    static func currentOffering() async throws -> Offering? {
        try await Purchases.shared.offerings().current
    }

    static func purchase(_ package: Package) async throws {
        _ = try await Purchases.shared.purchase(package: package)
    }

    static func restore() async throws {
        _ = try await Purchases.shared.restorePurchases()
    }
}
