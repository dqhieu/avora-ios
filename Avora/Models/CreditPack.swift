import Foundation

struct CreditPack: Codable, Identifiable {
    let productId: String
    let credits: Int
    let sortOrder: Int

    var id: String { productId }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case credits
        case sortOrder = "sort_order"
    }
}
