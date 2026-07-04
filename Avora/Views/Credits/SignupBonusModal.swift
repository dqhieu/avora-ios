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
            // Dimmed backdrop. contentShape + an empty tap gesture make it
            // intentionally absorb taps, blocking interaction with the app
            // behind the modal — but the gesture does nothing, so only the
            // Claim button ever dismisses.
            Color.black.opacity(0.25)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

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
            .background(Color.avoraSurface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
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
        Image("LoginBackground")
        SignupBonusModal(credits: 60) {}
    }
}
#endif
