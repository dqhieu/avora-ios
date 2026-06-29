import Foundation

struct Style: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleImagePath: String?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, active
        case sampleImagePath = "sample_image_path"
    }
}
