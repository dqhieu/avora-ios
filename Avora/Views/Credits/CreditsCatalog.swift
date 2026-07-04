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

    private struct Row { let pack: CreditPack; let package: Package; let price: Double }

    /// DB packs matched to their RevenueCat package (by product id), dropping any
    /// that are missing or unpriced. Shared by the pack grid and the weekly badge.
    private static func pricedRows(packs: [CreditPack], offering: Offering) -> [Row] {
        let byId = Dictionary(
            offering.availablePackages.map { ($0.storeProduct.productIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return packs.compactMap { pack in
            guard let pkg = byId[pack.productId] else { return nil }
            let price = NSDecimalNumber(decimal: pkg.storeProduct.price).doubleValue
            guard price > 0 else { return nil }
            return Row(pack: pack, package: pkg, price: price)
        }
    }

    /// Zip DB packs with RevenueCat packages (matched by product id), compute
    /// bonus %, mark the featured pack, and sort by price ascending.
    static func packOptions(packs: [CreditPack], offering: Offering) -> [CreditPackOption] {
        let rows = pricedRows(packs: packs, offering: offering)
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

    /// Bonus % of the weekly plan vs the cheapest pack's credits-per-price, using
    /// the same baseline as the pack badges. 0 when the weekly plan isn't a better
    /// rate, or when packs/price are unavailable.
    static func weeklyBonusPercent(weeklyCredits: Int, packs: [CreditPack], offering: Offering) -> Int {
        let rows = pricedRows(packs: packs, offering: offering)
        guard !rows.isEmpty, let weekly = weeklyPackage(offering: offering) else { return 0 }
        let weeklyPrice = NSDecimalNumber(decimal: weekly.storeProduct.price).doubleValue
        guard weeklyPrice > 0 else { return 0 }

        var priced = rows.map { CreditsMath.Priced(credits: $0.pack.credits, price: $0.price) }
        priced.append(CreditsMath.Priced(credits: weeklyCredits, price: weeklyPrice))
        return CreditsMath.bonusPercents(priced).last ?? 0
    }
}
