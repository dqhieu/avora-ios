import Foundation

enum GenStatus: String, Codable { case pending, completed, failed }

struct Generation: Codable, Identifiable, Hashable {
    let id: UUID
    let styleId: String?
    let status: GenStatus
    let outputPath: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case styleId = "style_id"
        case outputPath = "output_path"
        case createdAt = "created_at"
    }
}

struct GenerationResult: Codable {
    let status: GenStatus
    let outputPath: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case status
        case outputPath = "output_path"
        case errorCode = "error_code"
    }
}
