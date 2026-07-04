import SwiftUI

/// Tappable balance chip for the toolbar: credits icon + live balance.
struct CreditsBalancePill: View {
    let credits: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "centsign")
              if credits == -1 {
                ProgressView()
              } else {
                Text(credits, format: .number).monospacedDigit()
              }
            }
            .font(.avoraSubheadline)
            .foregroundStyle(Color.avoraTextPrimary)
        }
        .accessibilityLabel("Credits: \(credits). Buy more.")
    }
}

#if DEBUG
#Preview("Balance pill") {
    NavigationStack {
        Color.avoraBackground
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CreditsBalancePill(credits: 1240) {}
                }
            }
    }
}
#endif
