import SwiftUI

/// A draggable before/after comparison card. The styled "after" is shown over
/// the original "before"; a vertical seam the user drags left/right reveals one
/// against the other. Starts fully showing the after — drag toward the before
/// to compare. Mirrors the onboarding hero's seam, but user-driven rather than
/// auto-animated.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage

    /// Fraction of the image width, from the leading edge, covered by the after.
    /// 1 = after fully covers the before; 0 = only the before shows.
    @State private var reveal: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(for: before, in: geo.size)
            let cut = rect.minX + rect.width * reveal
            ZStack(alignment: .topLeading) {
                image(before)
                    .overlay(alignment: .topTrailing) { tag("Before", inset: rect) }
                image(after)
                    .overlay(alignment: .topTrailing) { tag("After", inset: rect) }
                    .mask(alignment: .leading) { Rectangle().frame(width: max(0, cut)) }
                seam(x: cut, minY: rect.minY, height: rect.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        reveal = min(1, max(0, (value.location.x - rect.minX) / rect.width))
                    }
            )
        }
    }

    private func image(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Glowing vertical seam with a grabber handle, echoing the app's scan line.
    private func seam(x: CGFloat, minY: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color.white).frame(width: 2.5, height: height).blur(radius: 6)
            Capsule().fill(Color.white).frame(width: 2.5, height: height)
            Circle().fill(Color.white).frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .position(x: x, y: minY + height / 2)
    }

    // Pinned to the top-right corner of the fitted image (not the letterbox).
    // The "After" copy rides on the masked layer, so it hides as the before is
    // revealed and the "Before" copy underneath takes over.
    private func tag(_ text: String, inset rect: CGRect) -> some View {
        Text(text)
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.avoraSurface.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
            .padding(.top, rect.minY + Spacing.sm)
            .padding(.trailing, rect.minX + Spacing.sm)
    }

    // The rect the aspect-fit image occupies inside the card, so the seam spans
    // and travels only over the photo, not the letterbox.
    private func fittedRect(for img: UIImage, in container: CGSize) -> CGRect {
        let imageAspect = img.size.width / max(img.size.height, 1)
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
        return CGRect(x: (container.width - width) / 2,
                      y: (container.height - height) / 2,
                      width: width, height: height)
    }
}
