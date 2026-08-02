//
//  ApplicationSnapshot.swift
//  monitor_helper
//

import Foundation

struct ApplicationSnapshot: Identifiable, Hashable {
    let id: UUID
    let appDynamicsId: String
    let name: String
    let displayName: String
    let health: HealthStatus
    let averageResponseTimeMs: Double?
    let callsPerMinute: Double?
    let errorsPerMinute: Double?
    let errorPercentage: Double?
    let activeIncidentCount: Int
    let nodesReporting: Int?
    let totalNodes: Int?
    let tiersReporting: Int?
    let totalTiers: Int?
    let worstCpuPercent: Double?
    let worstMemoryPercent: Double?
    let availabilityPercent: Double?
    let infrastructureHealth: HealthStatus
    let lastUpdatedAt: Date?
    let lastSuccessfulSyncAt: Date?
    let isStale: Bool
    let dataAgeMinutes: Int?
    let isFavorite: Bool

    var hasApplicationMetrics: Bool {
        averageResponseTimeMs != nil || callsPerMinute != nil || errorsPerMinute != nil
    }

    var freshnessSummary: String {
        if isStale, let dataAgeMinutes {
            return "Data stale (\(dataAgeMinutes)m)"
        }

        if !hasApplicationMetrics {
            return "Configuration pending"
        }

        return "Mobile summary"
    }

    var nodeSummary: String {
        guard let nodesReporting, let totalNodes else {
            return "No node data"
        }

        return "\(nodesReporting)/\(totalNodes) nodes"
    }

    var tierSummary: String {
        guard let tiersReporting, let totalTiers else {
            return "No tier data"
        }

        return "\(tiersReporting)/\(totalTiers) tiers"
    }

    var infrastructureSummary: String {
        "\(nodeSummary), \(tierSummary)"
    }
}
