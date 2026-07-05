import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    let subscriptionActive: Bool
    let subscriptionPeriodEnd: Date?
    var signupBonusSeen: Bool
    var username: String?
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
        case subscriptionActive = "subscription_active"
        case subscriptionPeriodEnd = "subscription_period_end"
        case signupBonusSeen = "signup_bonus_seen"
        case username
    }
}
