import SwiftUI

/// Plain display data for a consumable pack (no RevenueCat types → previewable).
struct CreditPackDisplay {
    let credits: Int
    let priceString: String
    let bonusPercent: Int
    let isFeatured: Bool
}

/// Small green "+N%" badge (hidden when bonus is 0).
private struct BonusBadge: View {
    let percent: Int
    let prominent: Bool
    var body: some View {
        Text(prominent ? "Best value · +\(percent)%" : "+\(percent)%")
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraOnAccent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Color.avoraSuccess, in: Capsule())
    }
}

/// Featured hero pack: badge + large credit amount + primary buy button.
struct FeaturedPackCard: View {
    let pack: CreditPackDisplay
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if pack.bonusPercent > 0 {
                BonusBadge(percent: pack.bonusPercent, prominent: true)
            }
            Text(pack.credits, format: .number)
                .font(.avoraLargeTitle.monospacedDigit())
                .foregroundStyle(Color.avoraTextPrimary)
            Text("credits")
                .font(.avoraFootnote)
                .foregroundStyle(Color.avoraTextSecondary)
            AvoraPrimaryButton(action: onBuy) {
                Text("Buy · \(pack.priceString)")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .avoraElevatedSurface(cornerRadius: Radius.lg)
    }
}

/// Compact grid cell for a non-featured pack.
struct PackGridCell: View {
    let pack: CreditPackDisplay
    let onBuy: () -> Void

    var body: some View {
        Button(action: onBuy) {
            VStack(spacing: Spacing.xs) {
                Text(pack.credits, format: .number)
                    .font(.avoraTitle3.monospacedDigit())
                    .foregroundStyle(Color.avoraTextPrimary)
                Text(pack.priceString)
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .avoraElevatedSurface(cornerRadius: Radius.md)
            .overlay(alignment: .topTrailing) {
                if pack.bonusPercent > 0 {
                    BonusBadge(percent: pack.bonusPercent, prominent: false)
                        .padding(Spacing.sm)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Pack cards") {
    let cols = [GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)]
    return VStack(spacing: Spacing.sm) {
        FeaturedPackCard(pack: .init(credits: 6000, priceString: "$39.99",
                                     bonusPercent: 50, isFeatured: true)) {}
        LazyVGrid(columns: cols, spacing: Spacing.sm) {
            PackGridCell(pack: .init(credits: 500, priceString: "$4.99", bonusPercent: 0, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 1000, priceString: "$9.99", bonusPercent: 0, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 2500, priceString: "$19.99", bonusPercent: 25, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 4000, priceString: "$29.99", bonusPercent: 33, isFeatured: false)) {}
        }
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
