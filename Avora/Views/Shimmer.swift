import SwiftUI

/// A self-animating diagonal light sweep, dropped into an overlay to signal that
/// the content underneath is loading (e.g. a photo being generated).
struct Shimmer: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.45), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: width * 0.6)
            .rotationEffect(.degrees(70))
            .offset(x: animate ? width : -width)
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}
