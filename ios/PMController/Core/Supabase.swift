//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

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

enum AppConfig {

    /// Nil rather than fatal. A missing key is a setup step someone has
    /// not done yet, not a programming error, and crashing on launch
    /// tells them nothing — RootView shows them what to fix instead.
    static let supabaseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty,
              !raw.contains("YOUR-PROJECT")
        else { return nil }
        return URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
    }()

    static let supabaseAnonKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              key != "your-anon-key"
        else { return nil }
        return key
    }()

    static var isConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    /// Set by a launch argument so the app can be driven in a Simulator —
    /// by CI, or by anyone without a Supabase project yet — using the
    /// canned data in PreviewData.swift. It never reaches a real build's
    /// hands: nothing in the UI can turn it on.
    /// Read through UserDefaults rather than by scanning the raw
    /// arguments, because Foundation's argument domain treats `-flag` as
    /// a KEY whose value is the next argument. A bare `-PMControllerPreview`
    /// would therefore swallow `-PMControllerPreviewRole` as its value and
    /// the role would silently never arrive. Both flags take a value:
    ///
    ///     -PMControllerPreview YES -PMControllerPreviewRole lead
    ///
    /// The argument domain is volatile and per-launch, so nothing here
    /// can persist into a real run.
    static var isPreview: Bool {
        UserDefaults.standard.bool(forKey: "PMControllerPreview")
    }

    /// Which canned person to sign in as in preview mode.
    static var previewPersona: String {
        UserDefaults.standard.string(forKey: "PMControllerPreviewRole") ?? "super"
    }
}

/// Globals are lazy in Swift, so this is never constructed in preview mode
/// or on an unconfigured build — which is exactly why nothing here needs
/// to guard against a missing key at call sites.
let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL ?? URL(string: "https://unconfigured.invalid")!,
    supabaseKey: AppConfig.supabaseAnonKey ?? "unconfigured"
)
