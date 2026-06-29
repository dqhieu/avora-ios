import Foundation

enum GenStatus: String, Codable { case pending, completed, failed }

struct Generation: Codable, Identifiable, Hashable {
    let id: UUID
    let styleId: String?
    let status: GenStatus
    let outputPath: String?
    let createdAt: Date?
}

struct GenerationResult: Codable {
    let status: GenStatus
    let outputPath: String?
    let errorCode: String?
}
