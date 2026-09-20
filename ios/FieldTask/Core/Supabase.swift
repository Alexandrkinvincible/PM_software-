import Foundation
import Supabase

// =====================================================================
// One client for the whole app.
//
// The anon key is the only key that ever ships. Every query it makes
// carries the signed-in user's JWT, so PostgREST evaluates the policies
// in 0002_rls.sql against that person. There is no "admin mode" in the
// app: privileged work goes to an Edge Function that holds the
// service-role key server-side.
// =====================================================================

enum Config {
    static let supabaseURL: URL = {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
        else {
            fatalError("""
                SUPABASE_URL is missing. Copy \
                FieldTask/Resources/Config.example.xcconfig to Config.xcconfig \
                and fill in your project.
                """)
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, key != "your-anon-key"
        else {
            fatalError("SUPABASE_ANON_KEY is missing. See Config.example.xcconfig.")
        }
        return key
    }()
}

let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey
)
