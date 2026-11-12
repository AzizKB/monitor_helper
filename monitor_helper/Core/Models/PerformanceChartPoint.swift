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
    var sumValue: Double? = nil
    var sampleCount: Int = 1
    var peakValue: Double? = nil
    var peakObservedAt: Date? = nil

    var id: Date { timestamp }
}

struct MetricChartSeries: Hashable {
    let metric: PerformanceMetric
    let points: [LiveMetricChartPoint]
    let windowStart: Date
    let windowEnd: Date
    let intervalMinutes: Int

    var timeDomain: ClosedRange<Date> { windowStart...windowEnd }

    // Separate line segments prevent drawing through missing intervals.
    var plottedPoints: [SegmentedMetricChartPoint] {
        var segment = 0
        return points.enumerated().map { index, point in
            if index > 0, point.timestamp.timeIntervalSince(points[index - 1].timestamp) > Double(intervalMinutes * 60) + 1 {
                segment += 1
            }
            return SegmentedMetricChartPoint(point: point, segment: segment)
        }
    }

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
        if metric == .averageResponseTime,
           points.allSatisfy({ $0.sumValue != nil && $0.countValue != nil }) {
            let count = points.compactMap(\.countValue).reduce(0, +)
            if count > 0 {
                return points.compactMap(\.sumValue).reduce(0, +) / Double(count)
            }
        }
        let samples = points.map(\.sampleCount).reduce(0, +)
        guard samples > 0 else { return nil }
        return points.reduce(0) { $0 + $1.value * Double($1.sampleCount) } / Double(samples)
    }
}

struct SegmentedMetricChartPoint: Identifiable {
    let point: LiveMetricChartPoint
    let segment: Int

    var id: Date { point.timestamp }
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
