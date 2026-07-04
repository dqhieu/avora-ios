import Foundation
import RevenueCat

/// One purchasable consumable pack: display data + the RevenueCat package.
struct CreditPackOption: Identifiable {
    let productId: String
    let display: CreditPackDisplay
    let package: Package
    var id: String { productId }
}

enum CreditsCatalog {
    static let weeklyProductId = "com.hieudinh.Avora.weekly"

    /// The weekly subscription package in the current offering, if present.
    static func weeklyPackage(offering: Offering) -> Package? {
        offering.availablePackages.first {
            $0.storeProduct.productIdentifier == weeklyProductId
        }
    }

    /// Zip DB packs with RevenueCat packages (matched by product id), compute
    /// bonus %, mark the featured pack, and sort by price ascending.
    static func packOptions(packs: [CreditPack], offering: Offering) -> [CreditPackOption] {
        let byId = Dictionary(
            offering.availablePackages.map { ($0.storeProduct.productIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        struct Row { let pack: CreditPack; let package: Package; let price: Double }
        let rows: [Row] = packs.compactMap { pack in
            guard let pkg = byId[pack.productId] else { return nil }
            let price = NSDecimalNumber(decimal: pkg.storeProduct.price).doubleValue
            guard price > 0 else { return nil }
            return Row(pack: pack, package: pkg, price: price)
        }
        guard !rows.isEmpty else { return [] }

        let priced = rows.map { CreditsMath.Priced(credits: $0.pack.credits, price: $0.price) }
        let bonuses = CreditsMath.bonusPercents(priced)
        let featured = CreditsMath.featuredIndex(priced)

        let options = rows.indices.map { i -> CreditPackOption in
            CreditPackOption(
                productId: rows[i].pack.productId,
                display: CreditPackDisplay(
                    credits: rows[i].pack.credits,
                    priceString: rows[i].package.storeProduct.localizedPriceString,
                    bonusPercent: bonuses[i],
                    isFeatured: i == featured
                ),
                package: rows[i].package
            )
        }
        return options.sorted { $0.display.credits < $1.display.credits }
    }
}
