import Foundation

/// How the community feed is ordered. `latest` paginates by `shared_at` (keyset);
/// `mostLiked` paginates by offset because the like count is mutable.
enum CommunitySort: String, CaseIterable, Hashable {
    case latest
    case mostLiked

    var label: String {
        switch self {
        case .latest: return "Latest"
        case .mostLiked: return "Most liked"
        }
    }
}

/// One row of the `community_feed` view: a publicly shared creation with its
/// author, like count, and whether the current user has liked it. A creation is
/// either style-based (`styleId`) or custom (`customPrompt`), never both.
struct CommunityItem: Codable, Identifiable, Hashable {
    let id: UUID
    let outputPath: String?
    let styleId: String?
    let customPrompt: String?
    var likeCount: Int
    let username: String?
    var likedByMe: Bool
    var sharedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username
        case outputPath = "output_path"
        case styleId = "style_id"
        case customPrompt = "custom_prompt"
        case likeCount = "like_count"
        case likedByMe = "liked_by_me"
        case sharedAt = "shared_at"
    }
}
