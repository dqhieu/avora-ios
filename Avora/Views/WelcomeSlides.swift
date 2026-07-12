import SwiftUI

/// Slide 1 artwork: a single before/after comparison card with an animated
/// vertical divider that sweeps to reveal the styled "after" over the "before".
/// Uses the bundled before/after pair when present; otherwise a real style
/// sample (styled "after" vs a desaturated "before") so it works with no assets.
struct WelcomeHero: View {
    let samplePath: String?
    let hasAssetPair: Bool

    @State private var divider: CGFloat = 0
    private let cardHeight: CGFloat = 360

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                beforeView
                    .frame(width: w, height: cardHeight).clipped()
                    .overlay(alignment: .topTrailing) { tag("Before").padding(10) }
                afterView
                    .frame(width: w, height: cardHeight).clipped()
                    .overlay(alignment: .topTrailing) { tag("After").padding(10) }
                    .mask(alignment: .leading) { Rectangle().frame(width: max(0, w * divider)) }
                dividerLine(x: w * divider)
            }
        }
        .frame(height: cardHeight)
        .clipShape(shape)
        .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                divider = 1
            }
        }
    }

    @ViewBuilder private var afterView: some View {
        if hasAssetPair {
            Image("OnboardingAfter").resizable().aspectRatio(contentMode: .fill)
        } else if let samplePath {
            RemoteImage(path: samplePath, source: .sample, contentMode: .fill)
        } else {
            Color.avoraSurface
        }
    }

    @ViewBuilder private var beforeView: some View {
        if hasAssetPair {
            Image("OnboardingBefore").resizable().aspectRatio(contentMode: .fill)
        } else if let samplePath {
            RemoteImage(path: samplePath, source: .sample, contentMode: .fill)
                .grayscale(1).contrast(1.05)
        } else {
            Color.avoraSurface.grayscale(1)
        }
    }

    // Glowing vertical seam with a grabber handle, echoing the app's scan line.
    private func dividerLine(x: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color.white).frame(width: 2.5, height: cardHeight).blur(radius: 6)
            Capsule().fill(Color.white).frame(width: 2.5, height: cardHeight)
            Circle().fill(Color.white).frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .position(x: x, y: cardHeight / 2)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.avoraSurface.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
    }
}

/// Slide 2 artwork: a staggered grid of real style samples that pops in on
/// appear — the "living gallery" of what's available. Falls back to glyph tiles
/// until styles load.
struct WelcomeStyleGallery: View {
    let paths: [String]
    @State private var shown = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let fallbackSymbols = ["photo", "sparkles", "paintbrush.pointed.fill",
                                   "camera.macro", "wand.and.stars", "face.smiling"]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let items = Array(paths.prefix(6))
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                shape.fill(Color.avoraSurface)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if i < items.count {
                            RemoteImage(path: items[i], source: .sample, contentMode: .fill)
                        } else {
                            Image(systemName: fallbackSymbols[i])
                                .font(.system(size: 22))
                                .foregroundStyle(Color.avoraTextSecondary)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
                    .scaleEffect(shown ? 1 : 0.5)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7)
                        .delay(Double(i) * 0.08), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}

/// Slide 3 artwork: the app's create icon with a gentle pulse.
struct WelcomeReadyArt: View {
    @State private var pulse = false
    var body: some View {
        ThiingIcon(name: "TabCreate", size: 128)
            .scaleEffect(pulse ? 1.06 : 0.92)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
