import SwiftUI

/// Non-interactive admission-ticket card announcing the free sign-in bonus.
/// Mirrors `CreditTicketCard`'s notched-yellow ticket look with no price rail
/// or buy action.
struct SignupBonusCard: View {
    let credits: Int

    private let notch: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            stub("BONUS")
                .frame(width: 34)
                .padding(.leading, 8)
            separator
            center
                .frame(maxWidth: .infinity)
            separator
            stub("AVORA")
                .frame(width: 34)
                .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .foregroundStyle(Color.avoraTicketInk)
        .background(Color.avoraTicketYellow, in: NotchedRectangle(notchRadius: notch))
        .overlay(NotchedRectangle(notchRadius: notch).strokeBorder(Color.avoraTicketInk, lineWidth: 1))
        .overlay(
            NotchedRectangle(notchRadius: notch - 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .foregroundStyle(Color.avoraTicketInk.opacity(0.55))
                .padding(6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sign-in bonus, \(credits) credits")
    }

    private var center: some View {
        VStack(spacing: Spacing.xs) {
            Text("✦  SIGN-IN BONUS  ✦").font(.avoraCaption2).tracking(3)
                .padding(.bottom, 8)
            rule
            Text(credits, format: .number).font(.avoraNumberLarge.monospacedDigit())
            rule
            Text("FREE CREDITS").font(.avoraCaption2).tracking(2)
                .padding(.top, 8)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.avoraTicketInk.opacity(0.35))
            .frame(width: 160, height: 1)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.avoraTicketInk.opacity(0.45))
            .frame(width: 1)
            .padding(.vertical, Spacing.lg)
    }

    private func stub(_ text: String) -> some View {
        Text(text)
            .font(.avoraCaption2)
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Signup bonus card") {
    SignupBonusCard(credits: 60)
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient)
}
#endif
