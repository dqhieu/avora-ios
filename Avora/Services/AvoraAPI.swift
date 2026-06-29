import Foundation
import Supabase

enum AvoraError: Error { case insufficientCredits, unauthorized, server(Int) }

struct AvoraAPI {
    static let shared = AvoraAPI()
    private static let iso8601 = ISO8601DateFormatter()
    private var db: SupabaseClient { SupabaseClientProvider.client }

    func currentUserId() async throws -> UUID {
        guard let user = db.auth.currentUser else { throw AvoraError.unauthorized }
        return user.id
    }

    func fetchStyles() async throws -> [Style] {
        try await db.from("styles_public")
            .select("id,name,sample_image_path,active")
            .eq("active", value: true)
            .order("name")
            .execute()
            .value
    }

    func fetchProfile() async throws -> Profile {
        let uid = try await currentUserId()
        return try await db.from("profiles")
            .select("weekly_credits,extra_credits")
            .eq("id", value: uid.uuidString)
            .single()
            .execute()
            .value
    }

    func uploadInput(_ data: Data) async throws -> String {
        let uid = try await currentUserId()
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString).png"
        try await db.storage.from("inputs")
            .upload(path, data: data, options: FileOptions(contentType: "image/png"))
        return path
    }

    func submit(styleId: String, inputPath: String) async throws -> UUID {
        struct Body: Encodable { let style_id: String; let input_path: String }
        struct Resp: Decodable { let job_id: UUID }
        do {
            let resp: Resp = try await db.functions.invoke(
                "submit-generation",
                options: .init(body: Body(style_id: styleId, input_path: inputPath))
            )
            return resp.job_id
        } catch let FunctionsError.httpError(code: code, data: _) where code == 402 {
            throw AvoraError.insufficientCredits
        } catch let FunctionsError.httpError(code: code, data: _) {
            throw AvoraError.server(code)
        }
    }

    func poll(jobId: UUID) async throws -> GenerationResult {
        try await db.functions.invoke(
            "get-generation",
            options: .init(
                method: .get,
                query: [URLQueryItem(name: "id", value: jobId.uuidString)]
            )
        )
    }

    func listGenerations(cursor: Date?) async throws -> (items: [Generation], next: Date?) {
        let baseQuery = db.from("generations")
            .select("id,style_id,status,output_path,created_at")
        let filtered = cursor.map { c in
            baseQuery.lt("created_at", value: AvoraAPI.iso8601.string(from: c))
        } ?? baseQuery
        let all: [Generation] = try await filtered
            .order("created_at", ascending: false)
            .limit(21)
            .execute()
            .value
        let items = Array(all.prefix(20))
        let next = all.count > 20 ? items.last?.createdAt : nil
        return (items, next)
    }

    func signedOutputURL(_ path: String) async throws -> URL {
        try await db.storage.from("outputs").createSignedURL(path: path, expiresIn: 3600)
    }

    func deleteAccount() async throws {
        let _: [String: Bool] = try await db.functions
            .invoke("delete-account", options: .init(method: .post))
        try await db.auth.signOut()
    }
}
