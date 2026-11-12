//
//  PerformanceSignalCard.swift
//  monitor_helper
//

import Charts
import SwiftUI

struct PerformanceSignalCard: View {
    let application: ApplicationSnapshot
    var selectedTimeRange: MonitoringTimeRange = .oneHour
    var selectedMetric: PerformanceMetric = .averageResponseTime
    var chartState: MetricChartLoadState = .empty
    var loadChart: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Signal")
                        .font(.headline)

                    Text("\(selectedTimeRange.displayName) • \(selectedMetric.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HealthBadge(status: application.health)
            }

            if application.hasApplicationMetrics {
                LiveMetricLineChartView(
                    metric: selectedMetric,
                    state: chartState,
                    retry: loadChart
                )
            } else {
                NoPerformanceMetricsView()
            }
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

struct LiveMetricLineChartView: View {
    let metric: PerformanceMetric
    let state: MetricChartLoadState
    var retry: (() async -> Void)?

    @State private var selectedTimestamp: Date?

    private var latestTimestamp: Date? {
        guard case let .loaded(series) = state else { return nil }
        return series.points.last?.timestamp
    }

    private var selectedPoint: LiveMetricChartPoint? {
        guard
            case let .loaded(series) = state,
            let selectedTimestamp
        else {
            return nil
        }

        return series.points.min {
            abs($0.timestamp.timeIntervalSince(selectedTimestamp)) < abs($1.timestamp.timeIntervalSince(selectedTimestamp))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .initial, .loading:
                ChartLoadingStateView()
            case let .loaded(series):
                chart(series: series)
                ChartWindowCaption(series: series)

                if let selectedPoint {
                    SelectedLiveMetricPointView(metric: metric, point: selectedPoint, intervalMinutes: series.intervalMinutes)
                } else {
                    ChartInstructionView()
                }
            case .empty:
                ChartEmptyStateView(metric: metric)
            case let .failed(message):
                ChartFailedStateView(message: message, retry: retry)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .onAppear {
            selectedTimestamp = latestTimestamp
        }
        .onChange(of: latestTimestamp) { _, newValue in
            selectedTimestamp = newValue
        }
    }

    private func chart(series: MetricChartSeries) -> some View {
        Chart {
            ForEach(series.plottedPoints) { plottedPoint in
                let point = plottedPoint.point
                LineMark(
                    x: .value("Observed", point.timestamp),
                    y: .value(metric.rawValue, point.value),
                    series: .value("Continuous segment", plottedPoint.segment)
                )
                .foregroundStyle(metric.color)
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Observed", point.timestamp),
                    y: .value(metric.rawValue, point.value)
                )
                .foregroundStyle(metric.color)
                .symbolSize(34)
            }

            if let averageValue = series.averageValue {
                RuleMark(y: .value("Average", averageValue))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected Time", selectedPoint.timestamp))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Selected", selectedPoint.timestamp),
                    y: .value(metric.rawValue, selectedPoint.value)
                )
                .foregroundStyle(metric.color)
                .symbolSize(90)
            }
        }
        .chartXScale(domain: series.timeDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedTimestamp)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
    }
}

struct LiveCallsErrorsChartView: View {
    let callsState: MetricChartLoadState
    let errorsState: MetricChartLoadState
    var retry: (() async -> Void)?

    @State private var selectedTimestamp: Date?

    private var callsSeries: MetricChartSeries? {
        guard case let .loaded(series) = callsState else { return nil }
        return series
    }

    private var errorsSeries: MetricChartSeries? {
        guard case let .loaded(series) = errorsState else { return nil }
        return series
    }

    private var combinedPoints: [CombinedMetricChartPoint] {
        let calls = normalizedPoints(from: callsSeries)
        let errors = normalizedPoints(from: errorsSeries)
        return (calls + errors).sorted { $0.timestamp < $1.timestamp }
    }

    private var chartSeries: MetricChartSeries? { callsSeries ?? errorsSeries }

    private var timeDomain: ClosedRange<Date> {
        chartSeries?.timeDomain ?? Date.distantPast...Date.distantFuture
    }

    private var isLoading: Bool {
        guard callsSeries == nil, errorsSeries == nil else { return false }

        if case .loading = callsState {
            return true
        }

        if case .loading = errorsState {
            return true
        }

        if case .initial = callsState {
            return true
        }

        if case .initial = errorsState {
            return true
        }

        return false
    }

    private var failureMessage: String? {
        if case let .failed(message) = callsState {
            return message
        }

        if case let .failed(message) = errorsState {
            return message
        }

        return nil
    }

    private var selectedCallsPoint: LiveMetricChartPoint? {
        nearestPoint(in: callsSeries, to: selectedTimestamp)
    }

    private var selectedErrorsPoint: LiveMetricChartPoint? {
        nearestPoint(in: errorsSeries, to: selectedTimestamp)
    }

    private var selectedDisplayTime: Date? {
        selectedCallsPoint?.timestamp ?? selectedErrorsPoint?.timestamp
    }

    private var latestTimestamp: Date? {
        [
            callsSeries?.points.last?.timestamp,
            errorsSeries?.points.last?.timestamp
        ]
            .compactMap { $0 }
            .max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ChartLoadingStateView()
            } else if combinedPoints.isEmpty, let failureMessage {
                ChartFailedStateView(message: failureMessage, retry: retry)
            } else if combinedPoints.isEmpty {
                CombinedChartEmptyStateView()
            } else {
                chart
                if let chartSeries {
                    ChartWindowCaption(series: chartSeries)
                }

                if let selectedDisplayTime {
                    SelectedCallsErrorsPointView(
                        timestamp: selectedDisplayTime,
                        intervalMinutes: chartSeries?.intervalMinutes ?? 1,
                        callsPoint: selectedCallsPoint,
                        errorsPoint: selectedErrorsPoint
                    )
                } else {
                    ChartInstructionView()
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .onAppear {
            selectedTimestamp = latestTimestamp
        }
        .onChange(of: latestTimestamp) { _, newValue in
            selectedTimestamp = newValue
        }
    }

    private var chart: some View {
        Chart {
            ForEach(combinedPoints) { point in
                LineMark(
                    x: .value("Observed", point.timestamp),
                    y: .value("Normalized Value", point.normalizedValue),
                    series: .value("Metric segment", "\(point.metric.metricKey)-\(point.segment)")
                )
                .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Observed", point.timestamp),
                    y: .value("Normalized Value", point.normalizedValue)
                )
                .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                .symbolSize(34)
            }

            if let selectedTimestamp {
                RuleMark(x: .value("Selected Time", selectedTimestamp))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: timeDomain)
        .chartForegroundStyleScale([
            PerformanceMetric.callsPerMinute.rawValue: PerformanceMetric.callsPerMinute.color,
            PerformanceMetric.errorsPerMinute.rawValue: PerformanceMetric.errorsPerMinute.color
        ])
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedTimestamp)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .overlay(alignment: .topTrailing) {
            Text("Normalized")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func normalizedPoints(from series: MetricChartSeries?) -> [CombinedMetricChartPoint] {
        guard let series else { return [] }

        let values = series.points.map(\.value)
        guard let minimumValue = values.min(), let maximumValue = values.max() else {
            return []
        }

        let range = maximumValue - minimumValue

        return series.plottedPoints.map { plottedPoint in
            let point = plottedPoint.point
            let normalizedValue: Double
            if range == 0 {
                normalizedValue = point.value == 0 ? 0 : 50
            } else {
                normalizedValue = (point.value - minimumValue) / range * 100
            }

            return CombinedMetricChartPoint(
                timestamp: point.timestamp,
                metric: series.metric,
                displayValue: point.value,
                normalizedValue: normalizedValue,
                segment: plottedPoint.segment
            )
        }
    }

    private func nearestPoint(
        in series: MetricChartSeries?,
        to selectedTimestamp: Date?
    ) -> LiveMetricChartPoint? {
        guard let series, let selectedTimestamp else { return nil }

        return series.points.min {
            abs($0.timestamp.timeIntervalSince(selectedTimestamp)) < abs($1.timestamp.timeIntervalSince(selectedTimestamp))
        }
    }
}

private struct CombinedMetricChartPoint: Identifiable {
    let timestamp: Date
    let metric: PerformanceMetric
    let displayValue: Double
    let normalizedValue: Double
    let segment: Int

    var id: String {
        "\(metric.metricKey)-\(timestamp.timeIntervalSince1970)"
    }
}

private struct ChartLoadingStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading chart data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
    }
}

private struct ChartEmptyStateView: View {
    let metric: PerformanceMetric

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No \(metric.shortTitle.lowercased()) data")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Supabase returned no datapoints for this app and time range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .padding(.horizontal, 16)
    }
}

private struct CombinedChartEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No calls or errors data")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Supabase returned no Calls per Minute or Errors per Minute datapoints for this app and time range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .padding(.horizontal, 16)
    }
}

private struct ChartFailedStateView: View {
    let message: String
    var retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)

            Text("Chart unavailable")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if let retry {
                Button("Retry") {
                    Task {
                        await retry()
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .padding(.horizontal, 16)
    }
}

private struct SelectedCallsErrorsPointView: View {
    let timestamp: Date
    let intervalMinutes: Int
    let callsPoint: LiveMetricChartPoint?
    let errorsPoint: LiveMetricChartPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .fontWeight(.semibold)
            if intervalMinutes > 1 {
                Text("\(intervalMinutes)-min average · \(timestamp.addingTimeInterval(-Double(intervalMinutes * 60)).formatted(date: .omitted, time: .shortened))–\(timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                SelectedMetricValue(
                    title: "CPM",
                    value: MetricFormatter.callsPerMinute(callsPoint?.value),
                    color: PerformanceMetric.callsPerMinute.color
                )

                SelectedMetricValue(
                    title: "EPM",
                    value: MetricFormatter.errorsPerMinute(errorsPoint?.value),
                    color: PerformanceMetric.errorsPerMinute.color
                )

                SelectedMetricValue(
                    title: "Error %",
                    value: MetricFormatter.percentage(errorPercentage),
                    color: .orange
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var errorPercentage: Double? {
        guard
            let callsPerMinute = callsPoint?.value,
            let errorsPerMinute = errorsPoint?.value,
            callsPerMinute > 0
        else {
            return nil
        }

        return errorsPerMinute / callsPerMinute * 100
    }
}

struct NoPerformanceMetricsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No performance data")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Average Response Time, Calls per Minute and Errors per Minute are not available for this range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .padding(.horizontal, 16)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

struct PerformanceLineGraphView: View {
    let application: ApplicationSnapshot
    let selectedTimeRange: MonitoringTimeRange

    @State private var selectedTimestamp: Date?

    private var points: [PerformanceChartPoint] {
        MockMonitoringData.performancePoints(for: application, range: selectedTimeRange)
    }

    private var samples: [PerformanceChartSample] {
        MockMonitoringData.performanceSamples(for: application, range: selectedTimeRange)
    }

    private var chartHeight: CGFloat {
        selectedTimeRange.minutes <= 30 ? 112 : 128
    }

    private var startDate: Date {
        points.map(\.timestamp).min() ?? .now
    }

    private var endDate: Date {
        points.map(\.timestamp).max() ?? .now
    }

    private var selectedSample: PerformanceChartSample? {
        guard let selectedTimestamp else { return nil }

        return samples.min {
            abs($0.timestamp.timeIntervalSince(selectedTimestamp)) < abs($1.timestamp.timeIntervalSince(selectedTimestamp))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if !points.isEmpty {
                    RectangleMark(
                        xStart: .value("Start", startDate),
                        xEnd: .value("End", endDate),
                        yStart: .value("Expected Low", 35),
                        yEnd: .value("Expected High", 65)
                    )
                    .foregroundStyle(.green.opacity(0.08))

                    RuleMark(y: .value("Expected", 50))
                        .foregroundStyle(.green.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    RuleMark(y: .value("Critical", 85))
                        .foregroundStyle(.red.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Normalized Value", point.normalizedValue),
                        series: .value("Metric", point.metric.rawValue)
                    )
                    .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Normalized Value", point.normalizedValue)
                    )
                    .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                    .symbolSize(34)
                }

                if let selectedSample {
                    RuleMark(x: .value("Selected Time", selectedSample.timestamp))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Selected Response Time", selectedSample.timestamp),
                        y: .value("Selected Response Time", selectedSample.averageResponseTime)
                    )
                    .foregroundStyle(PerformanceMetric.averageResponseTime.color)
                    .symbolSize(80)

                    PointMark(
                        x: .value("Selected Calls", selectedSample.timestamp),
                        y: .value("Selected Calls", selectedSample.callsPerMinute)
                    )
                    .foregroundStyle(PerformanceMetric.callsPerMinute.color)
                    .symbolSize(80)

                    PointMark(
                        x: .value("Selected Errors", selectedSample.timestamp),
                        y: .value("Selected Errors", selectedSample.errorsPerMinute)
                    )
                    .foregroundStyle(PerformanceMetric.errorsPerMinute.color)
                    .symbolSize(80)
                }
            }
            .chartForegroundStyleScale([
                PerformanceMetric.averageResponseTime.rawValue: PerformanceMetric.averageResponseTime.color,
                PerformanceMetric.callsPerMinute.rawValue: PerformanceMetric.callsPerMinute.color,
                PerformanceMetric.errorsPerMinute.rawValue: PerformanceMetric.errorsPerMinute.color
            ])
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedTimestamp)
            .frame(maxWidth: .infinity)
            .frame(height: chartHeight)
            .overlay {
                if points.isEmpty {
                    Text("No chart data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let selectedSample {
                SelectedPerformanceSampleView(sample: selectedSample)
            } else if !points.isEmpty {
                ChartInstructionView()
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

private struct SelectedPerformanceSampleView: View {
    let sample: PerformanceChartSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                SelectedMetricValue(
                    title: "ART",
                    value: "\(Int(sample.averageResponseTime))",
                    color: PerformanceMetric.averageResponseTime.color
                )
                SelectedMetricValue(
                    title: "CPM",
                    value: "\(Int(sample.callsPerMinute))",
                    color: PerformanceMetric.callsPerMinute.color
                )
                SelectedMetricValue(
                    title: "EPM",
                    value: "\(Int(sample.errorsPerMinute))",
                    color: PerformanceMetric.errorsPerMinute.color
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

private struct SelectedLiveMetricPointView: View {
    let metric: PerformanceMetric
    let point: LiveMetricChartPoint
    let intervalMinutes: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(point.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(metric.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if intervalMinutes > 1 {
                    Text("\(intervalMinutes)-min average · \(point.timestamp.addingTimeInterval(-Double(intervalMinutes * 60)).formatted(date: .omitted, time: .shortened))–\(point.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let peak = point.peakValue {
                        Text("Peak 1-min: \(metric.formatted(peak))")
                            .font(.caption2)
                            .foregroundStyle(metric.color)
                    }
                }
            }

            Spacer()

            Text(metric.formatted(point.value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(metric.color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

private struct ChartWindowCaption: View {
    let series: MetricChartSeries

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(boundary(series.windowStart))
            Spacer(minLength: 4)
            Text("\(series.intervalMinutes)-min intervals")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(boundary(series.windowEnd))
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private func boundary(_ date: Date) -> String {
        if series.windowEnd.timeIntervalSince(series.windowStart) >= 24 * 60 * 60 {
            return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct ChartInstructionView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
            Text("Tap or drag to inspect datapoints")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

private struct SelectedMetricValue: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

private struct GraphLegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PerformanceSignalCard(application: MockMonitoringData.applications[0])
        .padding()
        .background(AppTheme.groupedBackground)
}
