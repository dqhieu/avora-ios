import SwiftUI

/// A generation card that keeps the source photo sharp while a glowing accent
/// line sweeps top→bottom on a loop ("scanning"). When the result arrives, one
/// final sweep wipes the finished image in from the top: everything above the
/// line shows the result, everything below still shows the source, so the new
/// image is unveiled row by row. Replaces the blur-based FocusReveal.
struct ScanReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Seconds for one pass (down, then up) while waiting for the result.
    private let loopDuration: Double = 3.0
    /// Seconds for the single sweep that wipes the finished result in.
    private let revealDuration: Double = 1.2
    /// Height of the scan line in points.
    private let lineThickness: CGFloat = 2.5
    /// Blur radius of the glow copy behind the line.
    private let glowBlur: CGFloat = 8

    /// 0...1 looping line position while generating.
    @State private var scanY: CGFloat = 0
    /// 0...1 wipe position; also the height fraction of the revealed result.
    @State private var revealProgress: CGFloat = 0
    @State private var resultImage: UIImage?
    /// Once true, the visible line follows `revealProgress` instead of `scanY`.
    @State private var isRevealing = false
    @State private var lineOpacity: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let lineFraction = isRevealing ? revealProgress : scanY
            ZStack(alignment: .top) {
                cardImage(source)
                if let resultImage {
                    cardImage(resultImage)
                        .mask(alignment: .top) {
                            Rectangle().frame(height: h * revealProgress)
                        }
                }
                scanLine
                    .offset(y: h * lineFraction - lineThickness / 2)
                    .opacity(lineOpacity)
            }
            .frame(width: geo.size.width, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear { if isGenerating { startScanning() } }
        .onChange(of: isGenerating) { _, gen in if gen { startScanning() } }
        .task(id: resultPath) { await revealResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Thin accent line with a soft blurred glow copy behind it.
    private var scanLine: some View {
        ZStack {
            Capsule()
                .fill(Color.avoraAccent)
                .frame(height: lineThickness)
                .blur(radius: glowBlur)
            Capsule()
                .fill(Color.avoraAccent)
                .frame(height: lineThickness)
        }
        .frame(maxWidth: .infinity)
    }

    // Loop the line down→up→down while the job runs.
    private func startScanning() {
        guard resultImage == nil, !isRevealing else { return }
        lineOpacity = 1
        scanY = 0
        withAnimation(.easeInOut(duration: loopDuration).repeatForever(autoreverses: true)) {
            scanY = 1
        }
    }

    // Download the result, then run one top→bottom sweep that wipes it in.
    private func revealResult() async {
        guard let resultPath else { return }
        do {
            let img = try await ImageStore.shared.image(for: resultPath)
            resultImage = img
            isRevealing = true
            revealProgress = 0
            lineOpacity = 1
            withAnimation(.easeInOut(duration: revealDuration)) {
                revealProgress = 1
            } completion: {
                withAnimation(.easeOut(duration: 0.3)) { lineOpacity = 0 }
            }
        } catch {
            // Download failed: stop scanning, keep the sharp source, fade the line out.
            isRevealing = true
            withAnimation(.easeOut(duration: 0.3)) { lineOpacity = 0 }
        }
    }
}

#Preview {
    ScanReveal(
        source: UIImage(systemName: "photo.fill")!
            .withTintColor(.systemTeal, renderingMode: .alwaysOriginal),
        resultPath: nil,
        isGenerating: true
    )
    .frame(width: 300, height: 400)
    .padding()
}
