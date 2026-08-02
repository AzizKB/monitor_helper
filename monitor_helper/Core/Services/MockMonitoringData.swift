//
//  MockMonitoringData.swift
//  monitor_helper
//

import Foundation

enum MockMonitoringData {
    static let applications: [ApplicationSnapshot] = [
        ApplicationSnapshot(
            id: UUID(uuidString: "05E42386-F83B-49A8-A3CC-6B95D6EB9E25") ?? UUID(),
            appDynamicsId: "payment-gateway",
            name: "Payment Gateway",
            displayName: "Payment Gateway",
            health: .critical,
            averageResponseTimeMs: 2840,
            callsPerMinute: 1230,
            errorsPerMinute: 18,
            errorPercentage: 3.4,
            activeIncidentCount: 3,
            nodesReporting: 7,
            totalNodes: 8,
            tiersReporting: 4,
            totalTiers: 4,
            worstCpuPercent: 97,
            worstMemoryPercent: 82,
            availabilityPercent: 87.5,
            infrastructureHealth: .critical,
            lastUpdatedAt: .now.addingTimeInterval(-90),
            lastSuccessfulSyncAt: .now.addingTimeInterval(-60),
            isStale: false,
            dataAgeMinutes: 2,
            isFavorite: true
        ),
        ApplicationSnapshot(
            id: UUID(uuidString: "A308F3EE-E4F9-47A0-99D6-4696E8F917C4") ?? UUID(),
            appDynamicsId: "soa",
            name: "SOA",
            displayName: "SOA",
            health: .warning,
            averageResponseTimeMs: 620,
            callsPerMinute: 13_200,
            errorsPerMinute: 2.1,
            errorPercentage: 0.8,
            activeIncidentCount: 1,
            nodesReporting: 35,
            totalNodes: 36,
            tiersReporting: 5,
            totalTiers: 5,
            worstCpuPercent: 78,
            worstMemoryPercent: 68,
            availabilityPercent: 97.2,
            infrastructureHealth: .warning,
            lastUpdatedAt: .now.addingTimeInterval(-170),
            lastSuccessfulSyncAt: .now.addingTimeInterval(-60),
            isStale: false,
            dataAgeMinutes: 3,
            isFavorite: true
        ),
        ApplicationSnapshot(
            id: UUID(uuidString: "40384B1F-7B02-4C80-9C95-04140C751E7C") ?? UUID(),
            appDynamicsId: "crm",
            name: "CRM",
            displayName: "CRM",
            health: .healthy,
            averageResponseTimeMs: 144,
            callsPerMinute: 4200,
            errorsPerMinute: 0.2,
            errorPercentage: 0.1,
            activeIncidentCount: 0,
            nodesReporting: 12,
            totalNodes: 12,
            tiersReporting: 3,
            totalTiers: 3,
            worstCpuPercent: 42,
            worstMemoryPercent: 56,
            availabilityPercent: 100,
            infrastructureHealth: .healthy,
            lastUpdatedAt: .now.addingTimeInterval(-220),
            lastSuccessfulSyncAt: .now.addingTimeInterval(-60),
            isStale: false,
            dataAgeMinutes: 4,
            isFavorite: false
        ),
        ApplicationSnapshot(
            id: UUID(uuidString: "7F765512-A0AE-4EB9-860D-48E8BA3F24EE") ?? UUID(),
            appDynamicsId: "cbs",
            name: "CBS",
            displayName: "CBS",
            health: .noData,
            averageResponseTimeMs: nil,
            callsPerMinute: nil,
            errorsPerMinute: nil,
            errorPercentage: nil,
            activeIncidentCount: 0,
            nodesReporting: nil,
            totalNodes: nil,
            tiersReporting: nil,
            totalTiers: nil,
            worstCpuPercent: nil,
            worstMemoryPercent: nil,
            availabilityPercent: nil,
            infrastructureHealth: .noData,
            lastUpdatedAt: nil,
            lastSuccessfulSyncAt: .now.addingTimeInterval(-60),
            isStale: false,
            dataAgeMinutes: nil,
            isFavorite: false
        ),
        ApplicationSnapshot(
            id: UUID(uuidString: "D92AB6E4-58A1-4C8E-BE3F-7EC565F81C42") ?? UUID(),
            appDynamicsId: "wcs",
            name: "WCS",
            displayName: "WCS",
            health: .healthy,
            averageResponseTimeMs: 236,
            callsPerMinute: 760,
            errorsPerMinute: 0.4,
            errorPercentage: 0.2,
            activeIncidentCount: 0,
            nodesReporting: 9,
            totalNodes: 9,
            tiersReporting: 2,
            totalTiers: 2,
            worstCpuPercent: 38,
            worstMemoryPercent: 49,
            availabilityPercent: 100,
            infrastructureHealth: .healthy,
            lastUpdatedAt: .now.addingTimeInterval(-300),
            lastSuccessfulSyncAt: .now.addingTimeInterval(-60),
            isStale: false,
            dataAgeMinutes: 5,
            isFavorite: false
        )
    ]

    static func performancePoints(
        for application: ApplicationSnapshot,
        range: MonitoringTimeRange = .oneHour
    ) -> [PerformanceChartPoint] {
        performanceSamples(for: application, range: range).flatMap { sample in
            [
                PerformanceChartPoint(
                    timestamp: sample.timestamp,
                    metric: .averageResponseTime,
                    normalizedValue: sample.averageResponseTime
                ),
                PerformanceChartPoint(
                    timestamp: sample.timestamp,
                    metric: .callsPerMinute,
                    normalizedValue: sample.callsPerMinute
                ),
                PerformanceChartPoint(
                    timestamp: sample.timestamp,
                    metric: .errorsPerMinute,
                    normalizedValue: sample.errorsPerMinute
                )
            ]
        }
    }

    static func performanceSamples(
        for application: ApplicationSnapshot,
        range: MonitoringTimeRange = .oneHour
    ) -> [PerformanceChartSample] {
        let values = normalizedPerformanceValues(for: application.health, range: range)
        let duration = TimeInterval(range.minutes * 60)
        let start = Date.now.addingTimeInterval(-duration)
        let interval = duration / TimeInterval(max(values.count - 1, 1))

        return values.enumerated().map { index, point in
            let timestamp = start.addingTimeInterval(Double(index) * interval)

            return PerformanceChartSample(
                timestamp: timestamp,
                averageResponseTime: point.responseTime,
                callsPerMinute: point.calls,
                errorsPerMinute: point.errors
            )
        }
    }

    static func nodes(for application: ApplicationSnapshot) -> [NodeSnapshot] {
        switch application.health {
        case .critical:
            return [
                node(application, tier: "API", name: "pay-api-01", health: .critical, cpu: 97, memory: 83, availability: 100),
                node(application, tier: "API", name: "pay-api-02", health: .warning, cpu: 78, memory: 74, availability: 100),
                node(application, tier: "Services", name: "pay-svc-01", health: .healthy, cpu: 44, memory: 59, availability: 100),
                node(application, tier: "Database", name: "pay-db-01", health: .critical, cpu: 91, memory: 96, availability: 88)
            ]
        case .warning:
            return [
                node(application, tier: "Web", name: "soa-web-01", health: .healthy, cpu: 41, memory: 53, availability: 100),
                node(application, tier: "Services", name: "soa-svc-01", health: .warning, cpu: 78, memory: 68, availability: 100),
                node(application, tier: "Services", name: "soa-svc-02", health: .healthy, cpu: 54, memory: 61, availability: 100),
                node(application, tier: "Integration", name: "soa-int-01", health: .warning, cpu: 72, memory: 77, availability: 97)
            ]
        case .healthy:
            return [
                node(application, tier: "Web", name: "\(application.name.lowercased())-web-01", health: .healthy, cpu: 38, memory: 51, availability: 100),
                node(application, tier: "Services", name: "\(application.name.lowercased())-svc-01", health: .healthy, cpu: 42, memory: 56, availability: 100),
                node(application, tier: "Database", name: "\(application.name.lowercased())-db-01", health: .healthy, cpu: 35, memory: 49, availability: 100)
            ]
        case .noData:
            return []
        }
    }

    private static func normalizedPerformanceValues(
        for status: HealthStatus,
        range: MonitoringTimeRange
    ) -> [(responseTime: Double, calls: Double, errors: Double)] {
        let baseValues: [(responseTime: Double, calls: Double, errors: Double)]

        switch status {
        case .critical:
            baseValues = [
                (34, 48, 10),
                (38, 51, 14),
                (46, 55, 22),
                (58, 62, 38),
                (76, 68, 63),
                (91, 72, 86),
                (96, 75, 92)
            ]
        case .warning:
            baseValues = [
                (36, 42, 8),
                (39, 44, 9),
                (43, 49, 13),
                (51, 48, 24),
                (66, 52, 37),
                (59, 50, 30),
                (68, 55, 41)
            ]
        case .healthy:
            baseValues = [
                (40, 46, 7),
                (39, 45, 8),
                (42, 47, 6),
                (38, 46, 7),
                (43, 48, 9),
                (41, 47, 7),
                (40, 46, 7)
            ]
        case .noData:
            return []
        }

        guard range != .oneHour else { return baseValues }

        let targetCount: Int
        switch range {
        case .fifteenMinutes:
            targetCount = 4
        case .thirtyMinutes:
            targetCount = 5
        case .threeHours:
            targetCount = 10
        case .sixHours:
            targetCount = 14
        case .twelveHours, .twentyFourHours:
            targetCount = 20
        case .oneHour:
            targetCount = baseValues.count
        }

        return expandedValues(from: baseValues, targetCount: targetCount)
    }

    private static func expandedValues(
        from baseValues: [(responseTime: Double, calls: Double, errors: Double)],
        targetCount: Int
    ) -> [(responseTime: Double, calls: Double, errors: Double)] {
        guard !baseValues.isEmpty else { return [] }

        return (0..<targetCount).map { index in
            let base = baseValues[index % baseValues.count]
            let wave = Double((index % 4) - 1) * 3

            return (
                responseTime: clamped(base.responseTime + wave),
                calls: clamped(base.calls + wave / 2),
                errors: clamped(base.errors + wave * 1.2)
            )
        }
    }

    private static func clamped(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func node(
        _ application: ApplicationSnapshot,
        tier: String,
        name: String,
        health: HealthStatus,
        cpu: Double?,
        memory: Double?,
        availability: Double?
    ) -> NodeSnapshot {
        NodeSnapshot(
            id: UUID(),
            applicationID: application.id,
            tierName: tier,
            nodeName: name,
            health: health,
            cpuPercent: cpu,
            memoryPercent: memory,
            availabilityPercent: availability,
            lastUpdatedAt: application.lastUpdatedAt
        )
    }
}
