//
//  SupabaseConfiguration.swift
//  monitor_helper
//

import Foundation

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://jecrhdilcvetvzygeeqb.supabase.co")!

    // Publishable keys are safe for mobile clients. Never place the service-role
    // key or AppDynamics credentials in the iOS app.
    static let publishableKey = "sb_publishable_qTusiGzUUm_h1byI6JPisw_HseUIKSL"
}
