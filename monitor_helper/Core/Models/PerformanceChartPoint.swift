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

struct LiveMetricChartPoint: Identifiable, Hashable {
    let timestamp: Date
    let value: Double
    let currentValue: Double?
    let minimumValue: Double?
    let maximumValue: Double?
    let countValue: Int?

    var id: Date { timestamp }
}

struct MetricChartSeries: Hashable {
    let metric: PerformanceMetric
    let points: [LiveMetricChartPoint]

    var latestPoint: LiveMetricChartPoint? {
        points.last
    }

    var minimumValue: Double? {
        points.map(\.value).min()
    }

    var maximumValue: Double? {
        points.map(\.value).max()
    }

    var averageValue: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

enum MetricChartLoadState: Equatable {
    case initial
    case loading
    case loaded(MetricChartSeries)
    case empty
    case failed(String)
}

struct ChartCacheKey: Hashable {
    let applicationID: UUID
    let metric: PerformanceMetric
    let range: MonitoringTimeRange
}

enum PerformanceMetric: String, CaseIterable {
    case averageResponseTime = "Average Response Time"
    case callsPerMinute = "Calls per Minute"
    case errorsPerMinute = "Errors per Minute"

    var metricKey: String {
        switch self {
        case .averageResponseTime:
            return "response_time"
        case .callsPerMinute:
            return "calls_per_minute"
        case .errorsPerMinute:
            return "errors_per_minute"
        }
    }

    var shortTitle: String {
        switch self {
        case .averageResponseTime:
            return "Response"
        case .callsPerMinute:
            return "Calls"
        case .errorsPerMinute:
            return "Errors"
        }
    }

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

    func formatted(_ value: Double?) -> String {
        switch self {
        case .averageResponseTime:
            return MetricFormatter.responseTime(value)
        case .callsPerMinute:
            return MetricFormatter.callsPerMinute(value)
        case .errorsPerMinute:
            return MetricFormatter.errorsPerMinute(value)
        }
    }
}
