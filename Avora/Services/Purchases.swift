import Foundation
import RevenueCat

enum AvoraPurchases {
    static func configure(appUserID: String) {
        Purchases.logLevel = .warn
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: AvoraConfig.revenueCatAPIKey)
                .with(appUserID: appUserID)
                .build()
        )
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
