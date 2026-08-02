//
//  SupabaseDTOs.swift
//  monitor_helper
//

import Foundation

struct SupabaseAuthSession: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct SupabaseMonitorApplicationDTO: Decodable {
    let applicationID: UUID
    let appDynamicsID: Int?
    let applicationName: String
    let displayName: String?
    let performanceHealth: String?
    let infrastructureHealth: String?
    let overallHealth: String?
    let responseTimeMs: Double?
    let callsPerMinute: Double?
    let errorsPerMinute: Double?
    let errorPercentage: Double?
    let worstCpuPercent: Double?
    let worstMemoryPercent: Double?
    let availability: Double?
    let activeCriticalCount: Int?
    let activeWarningCount: Int?
    let activeIncidentCount: Int?
    let nodeCount: Int?
    let tierCount: Int?
    let latestApplicationMetricAt: String?
    let latestInfrastructureMetricAt: String?
    let lastSuccessfulSyncAt: String?
    let isStale: Bool?
    let dataAgeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case applicationID = "application_id"
        case appDynamicsID = "appdynamics_id"
        case applicationName = "application_name"
        case displayName = "display_name"
        case performanceHealth = "performance_health"
        case infrastructureHealth = "infrastructure_health"
        case overallHealth = "overall_health"
        case responseTimeMs = "response_time_ms"
        case callsPerMinute = "calls_per_minute"
        case errorsPerMinute = "errors_per_minute"
        case errorPercentage = "error_percentage"
        case worstCpuPercent = "worst_cpu_percent"
        case worstMemoryPercent = "worst_memory_percent"
        case availability
        case activeCriticalCount = "active_critical_count"
        case activeWarningCount = "active_warning_count"
        case activeIncidentCount = "active_incident_count"
        case nodeCount = "node_count"
        case tierCount = "tier_count"
        case latestApplicationMetricAt = "latest_application_metric_at"
        case latestInfrastructureMetricAt = "latest_infrastructure_metric_at"
        case lastSuccessfulSyncAt = "last_successful_sync_at"
        case isStale = "is_stale"
        case dataAgeMinutes = "data_age_minutes"
    }
}

struct SupabaseApplicationNodeDTO: Decodable {
    let applicationID: UUID
    let tierName: String?
    let nodeID: UUID
    let nodeName: String
    let cpuPercent: Double?
    let memoryPercent: Double?
    let availability: Double?
    let nodeHealth: String?
    let latestMetricAt: String?

    enum CodingKeys: String, CodingKey {
        case applicationID = "application_id"
        case tierName = "tier_name"
        case nodeID = "node_id"
        case nodeName = "node_name"
        case cpuPercent = "cpu_percent"
        case memoryPercent = "memory_percent"
        case availability
        case nodeHealth = "node_health"
        case latestMetricAt = "latest_metric_at"
    }
}

struct SupabaseChartPointDTO: Decodable {
    let observedAt: String
    let value: Double?

    enum CodingKeys: String, CodingKey {
        case observedAt = "observed_at"
        case value
    }
}

struct SupabaseIncidentDTO: Decodable {
    let violationID: UUID
    let applicationID: UUID
    let name: String
    let severity: String?
    let status: String?
    let description: String?
    let startTime: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case violationID = "violation_id"
        case applicationID = "application_id"
        case name
        case severity
        case status
        case description
        case startTime = "start_time"
        case durationSeconds = "duration_seconds"
    }
}
