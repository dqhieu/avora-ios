import Foundation

struct CreditConfig: Codable {
    let weeklyAmount: Int
    let signupExtra: Int
    let generationCost: Int
    let extraPack: Int

    enum CodingKeys: String, CodingKey {
        case weeklyAmount = "weekly_amount"
        case signupExtra = "signup_extra"
        case generationCost = "generation_cost"
        case extraPack = "extra_pack"
    }

    /// Baked-in defaults so the app works offline and before the first fetch.
    /// Must mirror the seed row in migration 000020_credit_config.sql.
    static let fallback = CreditConfig(
        weeklyAmount: 1000, signupExtra: 50, generationCost: 20, extraPack: 500
    )
}
