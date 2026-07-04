import SwiftUI

/// Primary weekly-subscription card. State-aware: subscribe CTA when inactive,
/// active status (no manage link) when the user already subscribes.
struct WeeklyPlanCard: View {
    let priceString: String?
    let isActive: Bool
    let renewsOn: Date?
    let onSubscribe: () -> Void

    private static let renews: Date.FormatStyle =
        .dateTime.month(.abbreviated).day()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isActive {
                Label("Weekly plan · Active", systemImage: "checkmark.seal.fill")
                    .font(.avoraCaption)
                    .foregroundStyle(Color.avoraSuccess)
            } else {
                Text("Weekly plan")
                    .font(.avoraCaption)
                    .foregroundStyle(Color.avoraTextSecondary)
            }

            (Text("1,200 credits").font(.avoraTitle2)
             + Text(" / week").font(.avoraSubheadline).foregroundColor(.avoraTextSecondary))
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
                if let priceString {
                    AvoraPrimaryButton(action: onSubscribe) {
                        Text("Subscribe · \(priceString)/week")
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .avoraElevatedSurface(cornerRadius: Radius.lg)
    }
}

#if DEBUG
#Preview("Weekly plan — states") {
    VStack(spacing: Spacing.lg) {
        WeeklyPlanCard(priceString: "$4.99", isActive: false, renewsOn: nil) {}
        WeeklyPlanCard(priceString: "$4.99", isActive: true,
                       renewsOn: .now.addingTimeInterval(7 * 86_400)) {}
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
