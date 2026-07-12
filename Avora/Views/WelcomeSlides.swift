import SwiftUI
import Combine

/// A single showcase frame in the welcome hero — either a bundled asset (the
/// real before/after pair) or a remote style sample.
enum WelcomeFrame {
    case asset(String)
    case remote(String)
}

/// The app's signature glowing scan line, reused as a decorative sweep over the
/// onboarding hero (mirrors `ScanReveal`'s generation animation).
private struct ScanLine: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color.white).frame(height: 2.5).blur(radius: 8)
            Capsule().fill(Color.white).frame(height: 2.5)
        }
    }
}

/// Slide 1 artwork: a large card that crossfades through styled results with a
/// slow zoom while the scan line sweeps — showing the "photo → art" magic even
/// before real before/after art is bundled.
struct WelcomeHero: View {
    let frames: [WelcomeFrame]

    @State private var index = 0
    @State private var zoom = false
    @State private var sweep = false

    private let cardHeight: CGFloat = 360
    private let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        ZStack {
            if frames.isEmpty {
                ZStack {
                    shape.fill(Color.avoraSurface)
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.avoraTextSecondary)
                }
            } else {
                ZStack {
                    ForEach(frames.indices, id: \.self) { i in
                        frameView(frames[i])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .opacity(i == index ? 1 : 0)
                    }
                }
                .scaleEffect(zoom ? 1.08 : 1.0)
            }

            VStack {
                ScanLine().padding(.horizontal, 10)
                Spacer(minLength: 0)
            }
            .offset(y: sweep ? cardHeight - 3 : 0)
        }
        .frame(height: cardHeight)
        .clipShape(shape)
        .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { sweep = true }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { zoom = true }
        }
        .onReceive(timer) { _ in
            guard frames.count > 1 else { return }
            withAnimation(.easeInOut(duration: 1.0)) { index = (index + 1) % frames.count }
        }
    }

    @ViewBuilder
    private func frameView(_ frame: WelcomeFrame) -> some View {
        switch frame {
        case .asset(let name):
            Image(name).resizable().aspectRatio(contentMode: .fill)
        case .remote(let path):
            RemoteImage(path: path, source: .sample, contentMode: .fill)
        }
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
