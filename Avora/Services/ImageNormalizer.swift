import UIKit

enum ImageNormalizer {
    static func normalize(_ image: UIImage, maxDimension: CGFloat = 1536) -> Data {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7) ?? Data()
    }
}
