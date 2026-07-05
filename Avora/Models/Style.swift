import Foundation

struct Style: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleImagePath: String?
    let active: Bool
    let sortOrder: Int
    let badgeText: String?

    enum CodingKeys: String, CodingKey {
        case id, name, active
        case sampleImagePath = "sample_image_path"
        case sortOrder = "sort_order"
        case badgeText = "badge_text"
    }
}

extension Style {
    /// Trimmed badge text to display, or nil when there is no meaningful badge.
    var displayBadge: String? {
        guard let badgeText,
              !badgeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return badgeText
    }

    /// Client-only navigation token for the custom-prompt flow. Never sent to the
    /// backend — custom generations submit `style_id: nil`. Provides the non-optional
    /// `Style` that `CreateRoute` and the navigation title need.
    static let custom = Style(
        id: "custom", name: "Custom", sampleImagePath: nil,
        active: false, sortOrder: -1, badgeText: nil
    )
}

