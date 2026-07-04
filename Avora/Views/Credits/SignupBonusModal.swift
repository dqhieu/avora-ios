import SwiftUI

/// One-time celebratory reveal of the sign-in bonus. A centered dialog over a
/// dimmed backdrop; only the "Claim" button dismisses (so the caller's
/// acknowledgement always runs — backdrop taps are ignored). Fires a confetti
/// burst + success haptic on appear (haptic is played inside ConfettiView).
struct SignupBonusModal: View {
    let credits: Int
    let onClaim: () -> Void

    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            // Dimmed backdrop. contentShape + a no-op-free gesture is avoided on
            // purpose: the backdrop swallows taps but never dismisses.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.xs) {
                    Text("Welcome to Avora!")
                        .font(.avoraTitle)
                        .foregroundStyle(Color.avoraTextPrimary)
                    Text("Here's a little something to get you started.")
                        .font(.avoraSubheadline)
                        .foregroundStyle(Color.avoraTextSecondary)
                        .multilineTextAlignment(.center)
                }

                SignupBonusCard(credits: credits)

                AvoraPrimaryButton(action: onClaim) {
                    Text("Claim")
                }
            }
            .padding(Spacing.xl)
            .background(Color.avoraSurface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.xl)

            ConfettiView(trigger: confettiTrigger)
                .allowsHitTesting(false)
        }
        .onAppear { confettiTrigger += 1 }
    }
}

#if DEBUG
#Preview("Signup bonus modal") {
    ZStack {
        LinearGradient.avoraBackgroundGradient.ignoresSafeArea()
        SignupBonusModal(credits: 60) {}
    }
}
#endif
