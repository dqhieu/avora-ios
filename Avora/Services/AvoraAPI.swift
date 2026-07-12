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
            .select("id,name,sample_image_path,active,sort_order,badge_text")
            .eq("active", value: true)
            .order("sort_order")
            .order("name")
            .execute()
            .value
    }

    func fetchProfile() async throws -> Profile {
        let uid = try await currentUserId()
        return try await db.from("profiles")
            .select("weekly_credits,extra_credits,subscription_active,subscription_period_end,signup_bonus_seen,username")
            .eq("id", value: uid.uuidString)
            .single()
            .execute()
            .value
    }

    func markSignupBonusSeen() async throws {
        try await db.rpc("mark_signup_bonus_seen").execute()
    }

    enum SetUsernameResult: String, Decodable { case ok, taken, invalid }

    func isUsernameAvailable(_ candidate: String) async throws -> Bool {
        try await db.rpc("is_username_available", params: ["candidate": candidate])
            .execute()
            .value
    }

    func setUsername(_ newUsername: String) async throws -> SetUsernameResult {
        let raw: String = try await db.rpc(
            "set_username", params: ["new_username": newUsername])
            .execute()
            .value
        return SetUsernameResult(rawValue: raw) ?? .invalid
    }

    func fetchCreditPacks() async throws -> [CreditPack] {
        try await db.from("credit_packs")
            .select("product_id,credits,sort_order")
            .eq("active", value: true)
            .order("sort_order")
            .execute()
            .value
    }

    func fetchCreditConfig() async throws -> CreditConfig {
        try await db.from("credit_config")
            .select("weekly_amount,signup_extra,generation_cost,extra_pack,cost_low,cost_medium,cost_high")
            .single()
            .execute()
            .value
    }

    func uploadInput(_ data: Data) async throws -> String {
        #if DEBUG
        if AvoraConfig.isMockGenerationEnabled { return "mock://input" }
        #endif
        let uid = try await currentUserId()
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString).jpg"
        try await db.storage.from("inputs")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    func submitBatch(styleId: String?, inputPaths: [String], quality: String,
                     customPrompt: String? = nil) async throws -> [UUID] {
        #if DEBUG
        if AvoraConfig.isMockGenerationEnabled { return inputPaths.map { _ in UUID() } }
        #endif
        struct Body: Encodable {
            let style_id: String?
            let input_paths: [String]
            let quality: String
            let custom_prompt: String?
        }
        struct Resp: Decodable { let job_ids: [UUID] }
        do {
            let resp: Resp = try await db.functions.invoke(
                "submit-generation-batch",
                options: .init(body: Body(
                    style_id: styleId, input_paths: inputPaths,
                    quality: quality, custom_prompt: customPrompt))
            )
            return resp.job_ids
        } catch let FunctionsError.httpError(code: code, data: _) where code == 402 {
            throw AvoraError.insufficientCredits
        } catch let FunctionsError.httpError(code: code, data: _) {
            throw AvoraError.server(code)
        }
    }

    func poll(jobId: UUID) async throws -> GenerationResult {
        #if DEBUG
        if AvoraConfig.isMockGenerationEnabled {
            try await Task.sleep(nanoseconds: AvoraConfig.mockGenerationDelayNanos)
            return GenerationResult(status: .completed, outputPath: AvoraConfig.mockResultPath, errorCode: nil)
        }
        #endif
        return try await db.functions.invoke(
            "get-generation",
            options: .init(
                method: .get,
                query: [URLQueryItem(name: "id", value: jobId.uuidString)]
            )
        )
    }

    func listGenerations(cursor: Date?) async throws -> (items: [Generation], next: Date?) {
        let baseQuery = db.from("generations")
            .select("id,style_id,custom_prompt,status,output_path,created_at,shared_at")
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

    private static let communityPageSize = 20

    func communityLatest(before cursor: Date?) async throws
        -> (items: [CommunityItem], next: Date?) {
        let base = db.from("community_feed")
            .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
        let filtered = cursor.map { c in
            base.lt("shared_at", value: AvoraAPI.iso8601.string(from: c))
        } ?? base
        let all: [CommunityItem] = try await filtered
            .order("shared_at", ascending: false)
            .limit(AvoraAPI.communityPageSize + 1)
            .execute()
            .value
        let items = Array(all.prefix(AvoraAPI.communityPageSize))
        let next = all.count > AvoraAPI.communityPageSize ? items.last?.sharedAt : nil
        return (items, next)
    }

    func communityMostLiked(offset: Int) async throws
        -> (items: [CommunityItem], next: Int?) {
        let size = AvoraAPI.communityPageSize
        let all: [CommunityItem] = try await db.from("community_feed")
            .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
            .order("like_count", ascending: false)
            .order("shared_at", ascending: false)
            .range(from: offset, to: offset + size)   // inclusive; fetches size+1
            .execute()
            .value
        let items = Array(all.prefix(size))
        let next = all.count > size ? offset + size : nil
        return (items, next)
    }

    /// Other publicly shared creations by one author, newest first, excluding the
    /// creation currently being viewed. Filters by username (unique per profile);
    /// no schema change needed. Returns [] when the author has no other shared work.
    func communityByUser(_ username: String, excluding id: UUID, limit: Int = 12) async throws
        -> [CommunityItem] {
        try await db.from("community_feed")
            .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
            .eq("username", value: username)
            .neq("id", value: id.uuidString)
            .order("shared_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func shareCreation(_ id: UUID) async throws {
        try await db.rpc("share_creation", params: ["gen_id": id.uuidString]).execute()
    }

    func unshareCreation(_ id: UUID) async throws {
        try await db.rpc("unshare_creation", params: ["gen_id": id.uuidString]).execute()
    }

    func likeCreation(_ id: UUID) async throws -> Int {
        try await db.rpc("like_creation", params: ["gen_id": id.uuidString])
            .execute().value
    }

    func unlikeCreation(_ id: UUID) async throws -> Int {
        try await db.rpc("unlike_creation", params: ["gen_id": id.uuidString])
            .execute().value
    }

    func signedOutputURL(_ path: String) async throws -> URL {
        try await db.storage.from("outputs").createSignedURL(path: path, expiresIn: 3600)
    }

    /// Stable public URL for a shared asset in the public `assets` bucket
    /// (e.g. a style's `sample_image_path`). No token churn, so it caches well.
    func sampleURL(_ path: String) throws -> URL {
        try db.storage.from("assets").getPublicURL(path: path)
    }

    func deleteAccount() async throws {
        let _: [String: Bool] = try await db.functions
            .invoke("delete-account", options: .init(method: .post))
    }

    func deleteCreation(_ id: UUID) async throws {
        struct Body: Encodable { let id: String }
        let _: [String: Bool] = try await db.functions.invoke(
            "delete-creation",
            options: .init(method: .post, body: Body(id: id.uuidString)))
    }
}
