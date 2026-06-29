import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
    }
}
