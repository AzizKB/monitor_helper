//
//  SupabaseModelMapper.swift
//  monitor_helper
//

import Foundation

enum SupabaseModelMapper {
    static func application(from dto: SupabaseMonitorApplicationDTO) -> ApplicationSnapshot {
        let overallHealth = HealthStatus(apiValue: dto.overallHealth)
        let infrastructureHealth = HealthStatus(apiValue: dto.infrastructureHealth)
        let lastMetricAt = SupabaseDateParser.date(from: dto.latestApplicationMetricAt)
        let lastInfrastructureAt = SupabaseDateParser.date(from: dto.latestInfrastructureMetricAt)
        let lastUpdatedAt = [lastMetricAt, lastInfrastructureAt].compactMap { $0 }.max()

        return ApplicationSnapshot(
            id: dto.applicationID,
            appDynamicsId: dto.appDynamicsID.map(String.init) ?? dto.applicationID.uuidString,
            name: dto.applicationName,
            displayName: dto.displayName ?? dto.applicationName,
            health: dto.isStale == true ? .noData : overallHealth,
            averageResponseTimeMs: dto.responseTimeMs,
            callsPerMinute: dto.callsPerMinute,
            errorsPerMinute: dto.errorsPerMinute,
            errorPercentage: nil,
            activeIncidentCount: dto.activeIncidentCount ?? 0,
            nodesReporting: dto.nodeCount,
            totalNodes: dto.nodeCount,
            tiersReporting: dto.tierCount,
            totalTiers: dto.tierCount,
            worstCpuPercent: dto.worstCpuPercent,
            worstMemoryPercent: dto.worstMemoryPercent,
            availabilityPercent: normalizedAvailability(dto.availability),
            infrastructureHealth: dto.isStale == true ? .noData : infrastructureHealth,
            lastUpdatedAt: lastUpdatedAt,
            isFavorite: false
        )
    }

    static func node(from dto: SupabaseApplicationNodeDTO) -> NodeSnapshot {
        NodeSnapshot(
            id: dto.nodeID,
            applicationID: dto.applicationID,
            tierName: dto.tierName ?? "Unknown Tier",
            nodeName: dto.nodeName,
            health: HealthStatus(apiValue: dto.nodeHealth),
            cpuPercent: dto.cpuPercent,
            memoryPercent: dto.memoryPercent,
            availabilityPercent: normalizedAvailability(dto.availability),
            lastUpdatedAt: SupabaseDateParser.date(from: dto.latestMetricAt)
        )
    }

    static func chartSample(
        timestamp: Date,
        responseTime: Double?,
        callsPerMinute: Double?,
        errorsPerMinute: Double?
    ) -> PerformanceChartSample {
        PerformanceChartSample(
            timestamp: timestamp,
            averageResponseTime: responseTime ?? 0,
            callsPerMinute: callsPerMinute ?? 0,
            errorsPerMinute: errorsPerMinute ?? 0
        )
    }

    private static func normalizedAvailability(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1 ? value * 100 : value
    }
}
