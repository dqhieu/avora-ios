import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    var totalCredits: Int { weeklyCredits + extraCredits }
    var totalGenerations: Int { totalCredits / 25 }
}
