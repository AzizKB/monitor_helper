//
//  NodeSnapshot.swift
//  monitor_helper
//

import Foundation

struct NodeSnapshot: Identifiable, Hashable {
    let id: UUID
    let applicationID: UUID
    let tierName: String
    let nodeName: String
    let health: HealthStatus
    let cpuPercent: Double?
    let memoryPercent: Double?
    let availabilityPercent: Double?
    let lastUpdatedAt: Date?

    // Matches the backend's live-node metric window, including collector delay.
    func isReporting(asOf date: Date = .now) -> Bool {
        guard let lastUpdatedAt else { return false }
        return lastUpdatedAt >= date.addingTimeInterval(-65 * 60)
    }
}
