import SwiftUI

/// Primary weekly-subscription card. State-aware: subscribe CTA when inactive,
/// active status (no manage link) when the user already subscribes.
struct WeeklyPlanCard: View {
    let weeklyCredits: Int
    let bonusPercent: Int
    let priceString: String?
    let isActive: Bool
    let renewsOn: Date?
    let onSubscribe: () -> Void

    private static let renews: Date.FormatStyle =
        .dateTime.month(.abbreviated).day()

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if isActive {
                    Label("Weekly plan · Active", systemImage: "checkmark.seal.fill")
                        .font(.avoraCaption)
                        .foregroundStyle(Color.avoraSuccess)
                } else {
                    HStack(spacing: Spacing.sm) {
                        Text("Weekly plan")
                            .font(.avoraCaption)
                            .foregroundStyle(Color.avoraTextSecondary)
                        if bonusPercent > 0 { bonusBadge }
                    }
                }

                creditsAndPrice
                    .foregroundStyle(Color.avoraTextPrimary)

                if isActive {
                    if let renewsOn {
                        Text("Renews \(renewsOn.formatted(Self.renews))")
                            .font(.avoraFootnote)
                            .foregroundStyle(Color.avoraTextSecondary)
                    }
                } else {
                    Text("Auto-renews · cancel anytime")
                        .font(.avoraFootnote)
                        .foregroundStyle(Color.avoraTextSecondary)
                }
            }

            Spacer(minLength: Spacing.sm)

            if !isActive, priceString != nil {
                subscribeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "1,200 credits / week · $4.99" — price folded in when available.
    private var creditsAndPrice: Text {
        var text = Text("\(weeklyCredits.formatted()) credits").font(.avoraSubheadline)
            + Text(" / week").font(.avoraSubheadline).foregroundColor(.avoraTextSecondary)
        if let priceString {
            text = text
                + Text(" · \(priceString)").font(.avoraSubheadline).foregroundColor(.avoraTextSecondary)
        }
        return text
    }

    /// "20% more credits" — value nudge vs one-time packs (inactive state only).
    private var bonusBadge: some View {
        Text("\(bonusPercent)% more credits")
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraSuccess)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(Color.avoraSuccess.opacity(0.15), in: Capsule())
    }

    private var subscribeButton: some View {
        Button(action: onSubscribe) {
            Text("Subscribe")
                .font(.avoraButton)
                .foregroundStyle(Color.avoraOnAccent)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .avoraGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Weekly plan — states") {
    VStack(spacing: Spacing.lg) {
        WeeklyPlanCard(weeklyCredits: 1200, bonusPercent: 20, priceString: "$9.99",
                       isActive: false, renewsOn: nil) {}
        WeeklyPlanCard(weeklyCredits: 1200, bonusPercent: 20, priceString: "$9.99",
                       isActive: true, renewsOn: .now.addingTimeInterval(7 * 86_400)) {}
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
