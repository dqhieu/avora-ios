import Foundation

enum AvoraConfig {
    static let supabaseURL: URL = URL(string: "https://dqdsuzmqlnheiokfboyv.supabase.co")!
    static let supabaseAnonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxZHN1em1xbG5oZWlva2Zib3l2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2MjQ3OTksImV4cCI6MjA5ODIwMDc5OX0.LGIGmJeO5CmzL3r_fuRQ2ksUL_MDaYmalrJrAw5n4RU"
    static let functionsBaseURL: URL = supabaseURL.appendingPathComponent("functions/v1")
    static let revenueCatAPIKey: String = "appl_ntflcZHcYyfOpVEQVePRhQzBXQC"

    static let privacyPolicyURL: URL = URL(string: "https://useavora.ai/privacy")!
    static let termsOfServiceURL: URL = URL(string: "https://useavora.ai/terms")!
}

#if DEBUG
extension AvoraConfig {
    /// UserDefaults key backing the DEBUG-only "Mock generation" toggle.
    static let mockGenerationKey = "mockGenerationEnabled"

    /// When on, Generate fakes the whole round-trip instead of hitting the backend.
    static var isMockGenerationEnabled: Bool {
        UserDefaults.standard.bool(forKey: mockGenerationKey)
    }

    /// Simulated backend latency before the fake result is "ready".
    static let mockGenerationDelayNanos: UInt64 = 10_000_000_000

    /// Sentinel result path; `ImageStore` maps it to the bundled asset below.
    static let mockResultPath = "mock://result"
    static let mockResultAssetName = "MockResult"
}
#endif
