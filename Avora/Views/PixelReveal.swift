import SwiftUI

/// A generation card that dissolves the source photo into pixel blocks while its
/// job runs, holds (with a gentle pulse) through the result download, then
/// sharpens the finished result into focus. Replaces `SparkleDrift`.
struct PixelReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Max block edge in points at full pixelation.
    private let maxBlock: CGFloat = 24
    /// How far the block size dips below max on each pulse.
    private let pulseDip: CGFloat = 4

    @State private var blockSize: CGFloat = 1
    @State private var resultImage: UIImage?
    @State private var resultOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            cardImage(source)
            if let resultImage {
                cardImage(resultImage).opacity(resultOpacity)
            }
        }
        .layerEffect(
            ShaderLibrary.pixellate(.float(blockSize)),
            maxSampleOffset: CGSize(width: maxBlock, height: maxBlock)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear { if isGenerating { startPixelating() } }
        .onChange(of: isGenerating) { _, gen in if gen { startPixelating() } }
        .task(id: resultPath) { await revealResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Ramp from sharp to full blocks, then breathe at max until the result lands.
    private func startPixelating() {
        withAnimation(.easeInOut(duration: 12.0)) {
            blockSize = maxBlock
        } completion: {
            guard resultImage == nil, isGenerating else { return }
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                blockSize = maxBlock - pulseDip
            }
        }
    }

    // Load the finished result, cross-fade it in beneath the blocks so there is
    // no content pop, then sharpen from the held block size to crisp.
    private func revealResult() async {
        guard let resultPath else { return }
        do {
            let img = try await ImageStore.shared.image(for: resultPath)
            resultImage = img
            withAnimation(.easeOut(duration: 0.8)) { resultOpacity = 1 }
            withAnimation(.easeInOut(duration: 3.0).delay(0.4)) { blockSize = 1 }
        } catch {
            // Download failed: sharpen the source back so the user still sees a photo.
            withAnimation(.easeInOut(duration: 3.0)) { blockSize = 1 }
        }
    }
}

#Preview {
    PixelReveal(
        source: UIImage(systemName: "photo.fill")!
            .withTintColor(.systemTeal, renderingMode: .alwaysOriginal),
        resultPath: nil,
        isGenerating: true
    )
    .frame(width: 300, height: 400)
    .padding()
}
