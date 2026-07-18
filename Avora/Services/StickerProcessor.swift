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
        let extent = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              !result.allInstances.isEmpty,
              let maskBuffer = try? result.generateScaledMaskForImage(
                forInstances: result.allInstances, from: handler)
        else { return nil }

        let source = CIImage(cgImage: cgImage)
        let rawMask = CIImage(cvPixelBuffer: maskBuffer).cropped(to: extent)
        let minSide = min(extent.width, extent.height)

        // Round off the segmentation's stair-stepped edges before anything is drawn,
        // so both the cutout and the border follow a clean silhouette.
        let smoothMask = smooth(rawMask, blur: max(1.5, minSide * 0.004), extent: extent)

        // Subject cut out along the smoothed silhouette (soft, anti-aliased edge).
        let cutout = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: smoothMask.applyingFilter("CIMaskToAlpha"),
        ])

        // Die-cut white border: grow the smoothed mask, smooth the grown contour again
        // for a clean rounded outer edge, then paint it white via mask→alpha.
        let borderRadius = max(6, minSide * borderFraction)
        let border = smoothMask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: borderRadius])
            .cropped(to: extent)
        let whiteBorder = smooth(border, blur: max(1.5, borderRadius * 0.5), extent: extent)
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
