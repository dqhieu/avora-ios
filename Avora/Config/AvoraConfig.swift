import Foundation

enum AvoraConfig {
    static let supabaseURL: URL = URL(string: "https://dqdsuzmqlnheiokfboyv.supabase.co")!
    static let supabaseAnonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxZHN1em1xbG5oZWlva2Zib3l2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2MjQ3OTksImV4cCI6MjA5ODIwMDc5OX0.LGIGmJeO5CmzL3r_fuRQ2ksUL_MDaYmalrJrAw5n4RU"
    static let functionsBaseURL: URL = supabaseURL.appendingPathComponent("functions/v1")
    static let revenueCatAPIKey: String = "appl_ntflcZHcYyfOpVEQVePRhQzBXQC"
}
