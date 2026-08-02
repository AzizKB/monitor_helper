//
//  IncidentSnapshot.swift
//  monitor_helper
//

import Foundation

struct IncidentSnapshot: Identifiable, Hashable {
    let id: UUID
    let applicationID: UUID
    let title: String
    let severity: HealthStatus
    let status: String
    let description: String?
    let startedAt: Date?
    let durationSeconds: Int?

    var cleanDescription: String? {
        guard let description else { return nil }

        let cleaned = description
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return cleaned.isEmpty ? nil : cleaned
    }

    var durationText: String {
        guard let durationSeconds else { return "--" }

        let minutes = durationSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}
