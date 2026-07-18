import SwiftUI

/// A generation card that keeps the source photo sharp while a glowing accent
/// line sweeps down→up→down on a loop ("scanning"). Once the result finishes
/// downloading it simply replaces the source — no reveal animation. Replaces
/// the blur-based FocusReveal.
struct ScanReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Seconds for one pass (down, then up) while waiting for the result.
    private let loopDuration: Double = 3.0
    /// Height of the scan line in points.
    private let lineThickness: CGFloat = 2.5
    /// Blur radius of the glow copy behind the line.
    private let glowBlur: CGFloat = 8

    /// 0...1 looping line position while generating.
    @State private var scanY: CGFloat = 0
    @State private var resultImage: UIImage?
    /// True if the result download failed — keep the source, drop the line.
    @State private var didFail = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                if let resultImage {
                    BeforeAfterSlider(before: source, after: resultImage)
                } else {
                    cardImage(source)
                    if isGenerating {
                        let fit = fittedImageRect(in: geo.size)
                        scanLine
                            .frame(width: fit.width)
                            .offset(y: fit.minY + fit.height * scanY - lineThickness / 2)
                    }
                }
            }
            .frame(width: geo.size.width, height: h)
        }
        .clipShape(Rectangle())
        .onAppear { if isGenerating { startScanning() } }
        .onChange(of: isGenerating) { _, gen in if gen { startScanning() } }
        .task(id: resultPath) { await loadResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Thin white line with a soft blurred glow copy behind it. Width is set by
    // the caller to match the fitted image.
    private var scanLine: some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(height: lineThickness)
                .blur(radius: glowBlur)
            Capsule()
                .fill(Color.white)
                .frame(height: lineThickness)
        }
    }

    // The rect the aspect-fit source image actually occupies inside the card,
    // so the scan line spans and travels only over the photo, not the letterbox.
    private func fittedImageRect(in container: CGSize) -> (minY: CGFloat, height: CGFloat, width: CGFloat) {
        let imageAspect = source.size.width / max(source.size.height, 1)
        let containerAspect = container.width / max(container.height, 1)
        let width: CGFloat
        let height: CGFloat
        if imageAspect > containerAspect {
            width = container.width
            height = container.width / imageAspect
        } else {
            height = container.height
            width = container.height * imageAspect
        }
        return (minY: (container.height - height) / 2, height: height, width: width)
    }

    // Loop the line down→up→down while the job runs.
    private func startScanning() {
        guard resultImage == nil, !didFail else { return }
        scanY = 0
        withAnimation(.easeInOut(duration: loopDuration).repeatForever(autoreverses: true)) {
            scanY = 1
        }
    }

    // Download the result and show it in place of the source once ready.
    private func loadResult() async {
        guard let resultPath else { return }
        do {
            resultImage = try await ImageStore.shared.image(for: resultPath)
        } catch {
            // Download failed: keep the sharp source and drop the scan line.
            didFail = true
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
