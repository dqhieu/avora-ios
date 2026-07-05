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
    /// True only while a job is actively scanning (line hidden before Generate).
    @State private var isScanning = false
    @State private var resultImage: UIImage?
    /// True if the result download failed — keep the source, drop the line.
    @State private var didFail = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                if let resultImage {
                    cardImage(resultImage)
                } else {
                    cardImage(source)
                    if isScanning {
                        scanLine
                            .offset(y: h * scanY - lineThickness / 2)
                    }
                }
            }
            .frame(width: geo.size.width, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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
        guard resultImage == nil, !didFail else { return }
        isScanning = true
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
