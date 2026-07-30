//
//  PerformanceChartPoint.swift
//  monitor_helper
//

import Foundation
import SwiftUI

struct PerformanceChartPoint: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let metric: PerformanceMetric
    let normalizedValue: Double
}

struct PerformanceChartSample: Identifiable, Hashable {
    let timestamp: Date
    let averageResponseTime: Double
    let callsPerMinute: Double
    let errorsPerMinute: Double

    var id: Date { timestamp }
}

enum PerformanceMetric: String, CaseIterable {
    case averageResponseTime = "Average Response Time"
    case callsPerMinute = "Calls per Minute"
    case errorsPerMinute = "Errors per Minute"

    var color: Color {
        switch self {
        case .averageResponseTime:
            return .blue
        case .callsPerMinute:
            return .green
        case .errorsPerMinute:
            return .red
        }
    }
}
