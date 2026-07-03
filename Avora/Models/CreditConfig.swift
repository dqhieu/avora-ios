import Foundation

struct CreditConfig: Codable {
    let weeklyAmount: Int
    let signupExtra: Int
    let generationCost: Int
    let extraPack: Int
    let costLow: Int
    let costMedium: Int
    let costHigh: Int

    enum CodingKeys: String, CodingKey {
        case weeklyAmount = "weekly_amount"
        case signupExtra = "signup_extra"
        case generationCost = "generation_cost"
        case extraPack = "extra_pack"
        case costLow = "cost_low"
        case costMedium = "cost_medium"
        case costHigh = "cost_high"
    }

    /// Credits charged per image for the given quality.
    func cost(for quality: GenerationQuality) -> Int {
        switch quality {
        case .default: costLow
        case .high:    costMedium
        case .ultra:   costHigh
        }
    }

    /// Baked-in defaults so the app works offline and before the first fetch.
    /// Must mirror the seed row in migrations 000020_credit_config.sql and
    /// 000027_per_quality_cost.sql.
    static let fallback = CreditConfig(
        weeklyAmount: 1000, signupExtra: 50, generationCost: 20, extraPack: 500,
        costLow: 20, costMedium: 30, costHigh: 100
    )
}
