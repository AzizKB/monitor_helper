//
//  MetricFormatter.swift
//  monitor_helper
//

import Foundation

enum MetricFormatter {
    static func responseTime(_ value: Double?) -> String {
        guard let value else { return "--" }

        if value >= 1000 {
            return String(format: "%.2f s", value / 1000)
        }

        return "\(Int(value.rounded())) ms"
    }

    static func callsPerMinute(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func errorsPerMinute(_ value: Double?) -> String {
        guard let value else { return "--" }

        if value < 10 {
            return value.formatted(.number.precision(.fractionLength(1)))
        }

        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func infrastructurePercentage(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "No recent data" }

        return date.formatted(.relative(presentation: .named))
    }
}
