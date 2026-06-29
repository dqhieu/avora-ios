import Foundation

struct Style: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleImagePath: String?
    let active: Bool
}

extension JSONDecoder {
    static let avora: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
