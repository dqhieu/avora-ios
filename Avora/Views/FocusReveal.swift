import SwiftUI

/// A generation card that eases the source photo out of focus while its job
/// runs, holds (with a gentle breathing blur) through the result download, then
/// pulls the finished result sharply into focus. Replaces the sparkle/pixelate
/// generation states.
struct FocusReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Max blur radius in points at full defocus.
    private let maxBlur: CGFloat = 16
    /// How far the blur eases back below max on each breath.
    private let pulseDip: CGFloat = 3

    @State private var blurRadius: CGFloat = 0
    @State private var resultImage: UIImage?
    @State private var resultOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            cardImage(source)
            if let resultImage {
                cardImage(resultImage).opacity(resultOpacity)
            }
        }
        .blur(radius: blurRadius)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear { if isGenerating { startDefocusing() } }
        .onChange(of: isGenerating) { _, gen in if gen { startDefocusing() } }
        .task(id: resultPath) { await revealResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Ease from sharp to full blur, then breathe near max until the result lands.
    private func startDefocusing() {
        withAnimation(.easeInOut(duration: 12.0)) {
            blurRadius = maxBlur
        } completion: {
            guard resultImage == nil, isGenerating else { return }
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                blurRadius = maxBlur - pulseDip
            }
        }
    }

    // Load the finished result, cross-fade it in beneath the blur so there is no
    // content pop, then pull it sharply into focus from the held blur.
    private func revealResult() async {
        guard let resultPath else { return }
        do {
            let img = try await ImageStore.shared.image(for: resultPath)
            resultImage = img
            withAnimation(.easeOut(duration: 0.5)) { resultOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.2).delay(0.2)) { blurRadius = 0 }
        } catch {
            // Download failed: pull the source back into focus so the user still sees a photo.
            withAnimation(.easeInOut(duration: 1.2)) { blurRadius = 0 }
        }
    }
}

#Preview {
    FocusReveal(
        source: UIImage(systemName: "photo.fill")!
            .withTintColor(.systemTeal, renderingMode: .alwaysOriginal),
        resultPath: nil,
        isGenerating: true
    )
    .frame(width: 300, height: 400)
    .padding()
}
