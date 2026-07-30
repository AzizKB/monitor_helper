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
}
