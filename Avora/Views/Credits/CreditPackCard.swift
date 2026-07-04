import SwiftUI

/// Plain display data for a consumable pack (no RevenueCat types → previewable).
struct CreditPackDisplay {
    let credits: Int
    let priceString: String
    let bonusPercent: Int
    let isFeatured: Bool
}

/// A thin straight line (horizontal or vertical) for dashed ticket rules/separators.
private struct TicketRule: Shape {
    var horizontal: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if horizontal {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return p
    }
}

/// Admission-ticket card for a consumable credit pack. The whole card is a buy button.
struct CreditTicketCard: View {
    let pack: CreditPackDisplay
    var prominent: Bool
    let onBuy: () -> Void

    private let notch: CGFloat = 14
    private var height: CGFloat { prominent ? 168 : 128 }

    var body: some View {
        Button(action: onBuy) { ticket }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var ticket: some View {
        HStack(spacing: 0) {
            verticalText("CREDIT PACK", bold: false)
                .frame(width: 34)
            separator
            centerContent
                .frame(maxWidth: .infinity)
            separator
            verticalText(pack.priceString, bold: true)
                .frame(width: 46)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .foregroundStyle(Color.avoraTicketInk)
        .background(Color.avoraTicketYellow, in: NotchedRectangle(notchRadius: notch))
        .overlay(NotchedRectangle(notchRadius: notch).strokeBorder(Color.avoraTicketInk, lineWidth: 2))
        .overlay(
            NotchedRectangle(notchRadius: notch - 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .foregroundStyle(Color.avoraTicketInk.opacity(0.55))
                .padding(6)
        )
    }

    @ViewBuilder private var centerContent: some View {
        if prominent {
            VStack(spacing: Spacing.xs) {
                Text("✦  BEST VALUE  ✦").font(.avoraCaption2).tracking(3)
                rule
                Text(pack.credits, format: .number).font(.avoraNumberLarge.monospacedDigit())
                rule
                Text(footerText).font(.avoraCaption2).tracking(1)
            }
            .padding(.horizontal, Spacing.sm)
        } else {
            VStack(spacing: Spacing.xs) {
                if pack.bonusPercent > 0 {
                    Text("+\(pack.bonusPercent)% BONUS").font(.avoraCaption2).tracking(2)
                }
                Text(pack.credits, format: .number)
                    .font(.avoraNumber.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("CREDITS").font(.avoraCaption2).tracking(2)
            }
        }
    }

    private var rule: some View {
        TicketRule(horizontal: true)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .foregroundStyle(Color.avoraTicketInk.opacity(0.35))
            .frame(width: 160, height: 1)
    }

    private var separator: some View {
        TicketRule(horizontal: false)
            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
            .foregroundStyle(Color.avoraTicketInk.opacity(0.45))
            .frame(width: 1)
            .padding(.vertical, Spacing.lg)
    }

    private func verticalText(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(bold ? .avoraSubheadline.monospacedDigit() : .avoraCaption2)
            .tracking(bold ? 0 : 2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(maxHeight: .infinity)
    }

    private var footerText: String {
        pack.bonusPercent > 0 ? "CREDITS · +\(pack.bonusPercent)% BONUS" : "CREDITS"
    }

    private var accessibilityText: String {
        var parts = ["Credit pack", "\(pack.credits) credits"]
        if pack.bonusPercent > 0 { parts.append("\(pack.bonusPercent) percent bonus") }
        parts.append(pack.priceString)
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Credit ticket cards") {
    let cols = [GridItem(.flexible(), spacing: Spacing.md),
                GridItem(.flexible(), spacing: Spacing.md)]
    return ScrollView {
        VStack(spacing: Spacing.md) {
            CreditTicketCard(pack: .init(credits: 6000, priceString: "$39.99",
                                         bonusPercent: 50, isFeatured: true), prominent: true) {}
            LazyVGrid(columns: cols, spacing: Spacing.md) {
                CreditTicketCard(pack: .init(credits: 2500, priceString: "$19.99",
                                             bonusPercent: 25, isFeatured: false), prominent: false) {}
                CreditTicketCard(pack: .init(credits: 1000, priceString: "$9.99",
                                             bonusPercent: 0, isFeatured: false), prominent: false) {}
                CreditTicketCard(pack: .init(credits: 4000, priceString: "$29.99",
                                             bonusPercent: 33, isFeatured: false), prominent: false) {}
                CreditTicketCard(pack: .init(credits: 500, priceString: "kr 99,00",
                                             bonusPercent: 0, isFeatured: false), prominent: false) {}
            }
        }
        .padding(Spacing.lg)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
