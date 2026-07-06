import SwiftUI
import UIKit

/// One-shot confetti burst overlay. Bump `trigger` to fire a new burst from the
/// centre of the view; it plays a success haptic, animates outward, and
/// self-clears. Sits above content and ignores touches.
struct ConfettiView: View {
    let trigger: Int
    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotationEffect(.degrees(piece.rotation))
                    .offset(x: piece.x, y: piece.y)
                    .opacity(piece.opacity)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        let bounds = UIScreen.main.bounds
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue,
                               .purple, .pink, .avoraTicketYellow]

        pieces = (0..<80).map { i in
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 200...max(bounds.width, bounds.height))
            return ConfettiPiece(
                id: i,
                color: colors[i % colors.count],
                size: CGSize(width: .random(in: 5...10), height: .random(in: 10...18)),
                x: 0, y: 0,
                endX: cos(angle) * distance,
                endY: sin(angle) * distance + .random(in: 80...200),
                rotation: .random(in: 0...360),
                endRotation: .random(in: 360...1080),
                opacity: 1
            )
        }

        Haptics.success()

        Task {
            try? await Task.sleep(nanoseconds: 16_000_000)
            withAnimation(.easeOut(duration: 2.5)) {
                for i in pieces.indices {
                    pieces[i].x = pieces[i].endX
                    pieces[i].y = pieces[i].endY
                    pieces[i].rotation += pieces[i].endRotation
                    pieces[i].opacity = 0
                }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            pieces.removeAll()
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let size: CGSize
    var x: CGFloat
    var y: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    var rotation: Double
    let endRotation: Double
    var opacity: Double
}
