import SwiftUI

/// Pure credit-pack economics — no RevenueCat/SwiftUI dependencies so it can be
/// exercised by the preview asserts below (this project has no unit-test target).
enum CreditsMath {
    struct Priced {
        let credits: Int
        let price: Double
    }

    /// Bonus percent per item vs the cheapest item's credits-per-price.
    /// A bonus that rounds to ≤ 1% is reported as 0 (no badge).
    static func bonusPercents(_ items: [Priced]) -> [Int] {
        guard let base = items.min(by: { $0.price < $1.price }), base.price > 0 else {
            return Array(repeating: 0, count: items.count)
        }
        let baseRate = Double(base.credits) / base.price   // credits per unit price
        return items.map { item in
            let expected = baseRate * item.price
            guard expected > 0 else { return 0 }
            let pct = (Double(item.credits) - expected) / expected * 100
            let rounded = Int(pct.rounded())
            return rounded <= 1 ? 0 : rounded
        }
    }

    /// Index of the featured item: highest bonus, ties broken by higher credits.
    /// Returns nil when no item has a bonus.
    static func featuredIndex(_ items: [Priced]) -> Int? {
        let bonuses = bonusPercents(items)
        var best: Int? = nil
        for i in items.indices where bonuses[i] > 0 {
            if best == nil
                || bonuses[i] > bonuses[best!]
                || (bonuses[i] == bonuses[best!] && items[i].credits > items[best!].credits) {
                best = i
            }
        }
        return best
    }
}

#if DEBUG
#Preview("CreditsMath checks") {
    let packs = [
        CreditsMath.Priced(credits: 500,  price: 4.99),
        CreditsMath.Priced(credits: 1000, price: 9.99),
        CreditsMath.Priced(credits: 2500, price: 19.99),
        CreditsMath.Priced(credits: 4000, price: 29.99),
        CreditsMath.Priced(credits: 6000, price: 39.99),
    ]
    let bonuses = CreditsMath.bonusPercents(packs)
    assert(bonuses == [0, 0, 25, 33, 50], "unexpected bonuses: \(bonuses)")
    assert(CreditsMath.featuredIndex(packs) == 4, "featured should be the 6,000 pack")

    return VStack(alignment: .leading, spacing: 8) {
        Text("✓ bonuses == [0, 0, 25, 33, 50]")
        Text("✓ featured == 6,000 pack")
    }
    .font(.avoraSubheadline)
    .padding()
}
#endif
