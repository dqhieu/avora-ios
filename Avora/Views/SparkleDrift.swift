import SwiftUI

/// Twinkling sparkles that drift upward and fade over a card, signalling that the
/// photo underneath is being generated. Echoes the wand.and.stars Generate icon.
struct SparkleDrift: View {
    private struct Sparkle: Identifiable {
        let id = UUID()
        let x: CGFloat        // 0...1 horizontal position within the card
        let y: CGFloat        // 0...1 resting vertical position
        let size: CGFloat
        let delay: Double
        let duration: Double
    }

    // Generated once so positions stay put across redraws.
    @State private var sparkles: [Sparkle] = (0..<14).map { _ in
        Sparkle(
            x: .random(in: 0.06...0.94),
            y: .random(in: 0.20...0.95),
            size: .random(in: 9...18),
            delay: .random(in: 0...1.6),
            duration: .random(in: 1.4...2.4)
        )
    }
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(sparkles) { sparkle in
                    Image(systemName: "sparkle")
                        .font(.system(size: sparkle.size))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.8), radius: 4)
                        .position(
                            x: sparkle.x * geo.size.width,
                            y: (animate ? sparkle.y - 0.12 : sparkle.y) * geo.size.height
                        )
                        .opacity(animate ? 0 : 1)
                        .scaleEffect(animate ? 1 : 0.4)
                        .animation(
                            .easeInOut(duration: sparkle.duration)
                                .repeatForever(autoreverses: true)
                                .delay(sparkle.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}
