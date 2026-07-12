import SwiftUI

/// One-time first-run walkthrough. Three passive slides that explain the value
/// prop and the core mechanic, then release the user into the app. Presented as
/// a full-screen cover by `ContentView`; `onFinish` is called once when the user
/// finishes the last slide or skips.
struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let slides = WelcomeSlide.all

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient.avoraBackgroundGradient.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    WelcomeSlideView(slide: slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            skipButton
        }
        .overlay(alignment: .bottom) { footer }
        .font(.avoraBody)
    }

    private var skipButton: some View {
        HStack {
            Spacer()
            Button("Skip") { Haptics.tap(); onFinish() }
                .font(.avoraSubheadline)
                .foregroundStyle(Color.avoraTextSecondary)
                .padding(Spacing.lg)
        }
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
            onFinish()
        } else {
            withAnimation { page += 1 }
        }
    }
}

private struct WelcomeSlide {
    enum Art { case beforeAfter, styleToPhoto, ready }
    let art: Art
    let title: String
    let subtitle: String

    static let all: [WelcomeSlide] = [
        WelcomeSlide(art: .beforeAfter,
                     title: "Turn your photos into art",
                     subtitle: "Pick a style and Avora restyles your photo with AI."),
        WelcomeSlide(art: .styleToPhoto,
                     title: "Pick a style, add your photo",
                     subtitle: "Tap any style, choose a photo, and we do the rest."),
        WelcomeSlide(art: .ready,
                     title: "Ready to create",
                     subtitle: "Your first credits are on us."),
    ]
}

private struct WelcomeSlideView: View {
    let slide: WelcomeSlide

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)
            artwork
            VStack(spacing: Spacing.md) {
                Text(slide.title)
                    .font(.avoraTitle)
                    .foregroundStyle(Color.avoraTextPrimary)
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 140) // clear the footer (dots + CTA)
    }

    @ViewBuilder
    private var artwork: some View {
        switch slide.art {
        case .beforeAfter:
            HStack(spacing: Spacing.md) {
                tile("OnboardingBefore", fallback: "photo")
                Image(systemName: "arrow.right")
                    .font(.avoraTitle2)
                    .foregroundStyle(Color.avoraTextSecondary)
                tile("OnboardingAfter", fallback: "sparkles")
            }
        case .styleToPhoto:
            HStack(spacing: Spacing.md) {
                glyphTile("square.grid.2x2")
                Image(systemName: "plus").foregroundStyle(Color.avoraTextSecondary)
                glyphTile("photo")
                Image(systemName: "arrow.right").foregroundStyle(Color.avoraTextSecondary)
                glyphTile("sparkles")
            }
        case .ready:
            ThiingIcon(name: "TabCreate", size: 112)
        }
    }

    // Before/after hero tiles. Uses the bundled asset when present; falls back to
    // an SF Symbol placeholder so the build ships before real art is delivered.
    @ViewBuilder
    private func tile(_ assetName: String, fallback symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName).resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.avoraTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.avoraSurface)
            }
        }
        .frame(width: 120, height: 160)
        .clipShape(shape)
        .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
    }

    private func glyphTile(_ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return Image(systemName: symbol)
            .font(.system(size: 26))
            .foregroundStyle(Color.avoraTextPrimary)
            .frame(width: 64, height: 64)
            .background(Color.avoraSurface, in: shape)
            .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
    }
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
    }
}

#if DEBUG
#Preview("Welcome carousel") {
    WelcomeView(onFinish: {})
}
#endif
