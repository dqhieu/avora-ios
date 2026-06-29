import Foundation
import Supabase

enum SupabaseClientProvider {
    static let client = SupabaseClient(
        supabaseURL: AvoraConfig.supabaseURL,
        supabaseKey: AvoraConfig.supabaseAnonKey
    )
}
