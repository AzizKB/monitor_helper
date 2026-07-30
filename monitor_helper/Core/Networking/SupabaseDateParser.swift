//
//  SupabaseDateParser.swift
//  monitor_helper
//

import Foundation

enum SupabaseDateParser {
    private static let formatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        return [fractional, standard]
    }()

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }

        let normalized = value.replacingOccurrences(of: " ", with: "T")

        for formatter in formatters {
            if let date = formatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }
}
