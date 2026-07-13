import SwiftUI

/// One-time first-run walkthrough. Three animated slides that *show* the core
/// loop — a photo transforming into art, the living style gallery, and a
/// celebratory finish — then release the user into the app. Presented as a
/// full-screen cover by `ContentView`; `onFinish` is called once when the user
/// finishes the last slide (Get Started).
struct WelcomeView: View {
    @Environment(AppState.self) private var app
    let onFinish: () -> Void

    @State private var page = 0
    @State private var confetti = 0

    private let slides = WelcomeSlide.all

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient.avoraBackgroundGradient.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    slidePage(i).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            ConfettiView(trigger: confetti).allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { footer }
        .font(.avoraBody)
        // Load the bonus data (config + profile) first so slide 3 can reveal the
        // real credit count, then the styles that feed slides 1–2.
        .task {
            await app.loadConfig()
            if app.profile == nil { await app.refreshProfile() }
            try? await app.loadStyles()
        }
        .onChange(of: page) { _, new in
            Haptics.selection()
            if new == slides.count - 1 { confetti += 1 }
        }
    }

    @ViewBuilder
    private func slidePage(_ i: Int) -> some View {
        let slide = slides[i]
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)
            artwork(for: slide.art)
            VStack(spacing: Spacing.md) {
                Text(slide.title)
                    .font(.avoraTitle)
                    .foregroundStyle(Color.avoraTextPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle(for: slide))
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .multilineTextAlignment(.center)
            }
            // Text rises + fades in as its slide becomes active.
            .offset(y: page == i ? 0 : 14)
            .opacity(page == i ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: page)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, 150) // clear the footer (dots + CTA)
    }

    @ViewBuilder
    private func artwork(for art: WelcomeSlide.Art) -> some View {
        switch art {
        case .hero: WelcomeHero(samplePath: galleryPaths.first, hasAssetPair: hasOnboardingPair)
        case .gallery: WelcomeStyleGallery(paths: galleryPaths)
        case .ready: WelcomeReadyArt(credits: bonusCredits)
        }
    }

    // The unclaimed sign-up bonus amount, or nil when there's no bonus to reveal
    // (already claimed, none configured, or config/profile not yet loaded).
    private var bonusCredits: Int? {
        guard app.profile?.signupBonusSeen == false, app.config.signupExtra > 0 else { return nil }
        return app.config.signupExtra
    }

    // Slide 3 promises the bonus only when there's one to show; otherwise it
    // stays generic so a no-bonus/already-claimed user isn't over-promised.
    private func subtitle(for slide: WelcomeSlide) -> String {
        if case .ready = slide.art, bonusCredits == nil {
            return "Let's make something."
        }
        return slide.subtitle
    }

    // Real before/after pair once both assets are bundled; until then the hero
    // falls back to a style sample (styled "after" vs a desaturated "before").
    private var hasOnboardingPair: Bool {
        UIImage(named: "OnboardingBefore") != nil && UIImage(named: "OnboardingAfter") != nil
    }

    private var galleryPaths: [String] {
        app.styles.compactMap(\.sampleImagePath)
    }

    private var footer: some View {
        VStack(spacing: Spacing.lg) {
            WelcomePageDots(count: slides.count, current: page)
            AvoraPrimaryButton(action: advance) {
                Text(page == slides.count - 1 ? "Get Started" : "Next")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.xxl)
    }

    private func advance() {
        Haptics.impact()
        if page == slides.count - 1 {
            // Getting Started from the last slide claims the bonus it just showed.
            if bonusCredits != nil { Task { await app.markSignupBonusSeen() } }
            onFinish()
        } else {
            withAnimation { page += 1 }
        }
    }
}

struct WelcomeSlide {
    enum Art { case hero, gallery, ready }
    let art: Art
    let title: String
    let subtitle: String

    static let all: [WelcomeSlide] = [
        WelcomeSlide(art: .hero,
                     title: "Turn your photos into art",
                     subtitle: "Avora restyles your photo with AI in seconds."),
        WelcomeSlide(art: .gallery,
                     title: "Pick a style, add your photo",
                     subtitle: "Dozens of styles — tap one, choose a photo, done."),
        WelcomeSlide(art: .ready,
                     title: "Ready to create",
                     subtitle: "Your first credits are on us."),
    ]
}

private struct WelcomePageDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.avoraTextPrimary
                                       : Color.avoraTextSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(.easeInOut, value: current)
    }
}

#if DEBUG
#Preview("Welcome — with bonus") {
    let app = AppState()
    app.profile = Profile(weeklyCredits: 1000, extraCredits: 0, subscriptionActive: false,
                          subscriptionPeriodEnd: nil, signupBonusSeen: false, username: nil)
    app.config = CreditConfig(weeklyAmount: 1000, signupExtra: 60, generationCost: 20,
                              extraPack: 500, costLow: 20, costMedium: 30, costHigh: 120)
    return WelcomeView(onFinish: {}).environment(app)
}

#Preview("Welcome — no bonus") {
    WelcomeView(onFinish: {}).environment(AppState())
}
#endif
