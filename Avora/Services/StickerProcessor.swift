import UIKit
import Vision
import CoreImage

/// Builds a die-cut sticker from a photo entirely on-device — no network, no
/// generation, so the subject's pixels are preserved exactly. Vision segments the
/// subject; the mask is smoothed to remove jagged edges, grown into a clean white
/// die-cut border, and the cutout is composited over it on a transparent background.
nonisolated enum StickerProcessor {
    /// Border thickness as a fraction of the image's shorter side.
    private static let borderFraction: CGFloat = 0.02

    private static let context = CIContext()

    /// Produces the sticker as a transparent PNG-backed image, or `nil` if no subject
    /// is found or processing fails. Heavy work runs off the main actor; input/output
    /// cross the boundary as `Data` so nothing non-Sendable is captured.
    static func makeSticker(from image: UIImage) async -> UIImage? {
        guard let input = image.normalizedUp().pngData() else { return nil }
        let output = await Task.detached(priority: .userInitiated) {
            renderPNG(from: input)
        }.value
        return output.flatMap(UIImage.init(data:))
    }

    private static func renderPNG(from pngData: Data) -> Data? {
        guard let cgImage = UIImage(data: pngData)?.cgImage else { return nil }
        let imageExtent = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              !result.allInstances.isEmpty,
              let maskBuffer = try? result.generateScaledMaskForImage(
                forInstances: result.allInstances, from: handler)
        else { return nil }

        let minSide = min(imageExtent.width, imageExtent.height)
        let borderRadius = max(6, minSide * borderFraction)

        // Pad the canvas so the die-cut border can grow outward even where the
        // subject reaches the photo edge; without this margin the border would be
        // clipped flush on those sides and the outline would look cut off.
        let pad = ceil(borderRadius * 1.5)
        let extent = imageExtent.insetBy(dx: -pad, dy: -pad)
        let offset = CGAffineTransform(translationX: pad, y: pad)

        let photoRect = imageExtent.applying(offset)
        let silhouetteBlur = max(1.5, minSide * 0.004)
        let source = CIImage(cgImage: cgImage).transformed(by: offset)
        let rawMask = CIImage(cvPixelBuffer: maskBuffer).cropped(to: imageExtent).transformed(by: offset)

        // Subject mask. Smooth the silhouette, but where the photo frame truncates the
        // subject keep the edge crisp: clamping replicates the boundary pixels so the
        // blur can't fade a solid edge into transparency (which looked like a shadow).
        // Confined to the photo rect — the subject never spills into the pad.
        let subjectMask = smooth(rawMask.clampedToExtent(), blur: silhouetteBlur, extent: photoRect)
        let cutout = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: subjectMask.applyingFilter("CIMaskToAlpha"),
        ]).cropped(to: photoRect)

        // Die-cut white border: grow the *hard* raw mask (not the already-softened
        // subject mask) outward, then `smooth` it. Growing the hard mask matters — the
        // contrast step in `smooth` can only snap a hard edge back to a crisp outline;
        // a pre-softened edge just spreads into a wide fade. The small blur rounds off
        // the morphology's disc faceting so the contour stays smooth.
        let border = rawMask.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: borderRadius])
            .cropped(to: extent)
        let whiteBorder = smooth(border, blur: max(1.5, borderRadius * 0.15), extent: extent)
            .applyingFilter("CIMaskToAlpha")

        // Subject over white border over transparent.
        let composite = cutout.composited(over: whiteBorder)

        guard let out = context.createCGImage(composite, from: extent) else { return nil }
        return UIImage(cgImage: out).pngData()
    }

    /// Blur then re-steepen the value ramp: removes jagged stair-stepping while keeping
    /// a defined (anti-aliased) edge, instead of a soft fade.
    private static func smooth(_ mask: CIImage, blur: Double, extent: CGRect) -> CIImage {
        mask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 6.0])
            .applyingFilter("CIColorClamp")
    }
}

private extension UIImage {
    /// Redraws the image with `.up` orientation so its `cgImage` pixels match the
    /// coordinate space Vision and Core Image work in.
    nonisolated func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
