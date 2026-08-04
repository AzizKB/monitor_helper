//
//  SupabaseModelMapper.swift
//  monitor_helper
//

import Foundation

enum SupabaseModelMapper {
    static func mobileAccess(from dto: SupabaseMobileAccessDTO) -> MobileAccessStatus {
        MobileAccessStatus(
            userID: dto.userID,
            email: dto.email,
            decision: MobileAccessDecision(rawValue: dto.status ?? "") ?? .unknown,
            role: dto.role,
            requestedAt: SupabaseDateParser.date(from: dto.requestedAt),
            approvedAt: SupabaseDateParser.date(from: dto.approvedAt)
        )
    }

    static func application(from dto: SupabaseMonitorApplicationDTO) -> ApplicationSnapshot {
        let overallHealth = HealthStatus(apiValue: dto.overallHealth)
        let infrastructureHealth = HealthStatus(apiValue: dto.infrastructureHealth)
        let lastMetricAt = SupabaseDateParser.date(from: dto.latestApplicationMetricAt)
        let lastInfrastructureAt = SupabaseDateParser.date(from: dto.latestInfrastructureMetricAt)
        let lastUpdatedAt = [lastMetricAt, lastInfrastructureAt].compactMap { $0 }.max()
        let lastSuccessfulSyncAt = SupabaseDateParser.date(from: dto.lastSuccessfulSyncAt)

        return ApplicationSnapshot(
            id: dto.applicationID,
            appDynamicsId: dto.appDynamicsID.map(String.init) ?? dto.applicationID.uuidString,
            name: dto.applicationName,
            displayName: dto.displayName ?? dto.applicationName,
            health: overallHealth,
            averageResponseTimeMs: dto.responseTimeMs,
            callsPerMinute: dto.callsPerMinute,
            errorsPerMinute: dto.errorsPerMinute,
            errorPercentage: dto.errorPercentage,
            activeIncidentCount: dto.activeIncidentCount ?? 0,
            nodesReporting: dto.nodeCount,
            totalNodes: dto.nodeCount,
            tiersReporting: dto.tierCount,
            totalTiers: dto.tierCount,
            worstCpuPercent: dto.worstCpuPercent,
            worstMemoryPercent: dto.worstMemoryPercent,
            availabilityPercent: normalizedAvailability(dto.availability),
            infrastructureHealth: infrastructureHealth,
            lastUpdatedAt: lastUpdatedAt,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            isStale: dto.isStale == true,
            dataAgeMinutes: dto.dataAgeMinutes,
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

    static func incident(from dto: SupabaseIncidentDTO) -> IncidentSnapshot {
        IncidentSnapshot(
            id: dto.violationID,
            applicationID: dto.applicationID,
            title: dto.name,
            severity: HealthStatus(apiValue: dto.severity),
            status: dto.status ?? "Unknown",
            description: dto.description,
            startedAt: SupabaseDateParser.date(from: dto.startTime),
            durationSeconds: dto.durationSeconds
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

    static func chartPoint(from dto: SupabaseChartPointDTO) -> LiveMetricChartPoint? {
        guard
            let timestamp = SupabaseDateParser.date(from: dto.observedAt),
            let value = dto.value
        else {
            return nil
        }

        return LiveMetricChartPoint(
            timestamp: timestamp,
            value: value,
            currentValue: dto.currentValue,
            minimumValue: dto.minimumValue,
            maximumValue: dto.maximumValue,
            countValue: dto.countValue
        )
    }

    private static func normalizedAvailability(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1 ? value * 100 : value
    }
}
