//
//  PerformanceSignalCard.swift
//  monitor_helper
//

import Charts
import SwiftUI

struct PerformanceSignalCard: View {
    let application: ApplicationSnapshot
    var selectedTimeRange: MonitoringTimeRange = .oneHour

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Signal")
                        .font(.headline)

                    Text("\(selectedTimeRange.displayName) normalized signal until Supabase chart data is connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HealthBadge(status: application.health)
            }

            if application.hasApplicationMetrics {
                PerformanceLineGraphView(
                    application: application,
                    selectedTimeRange: selectedTimeRange
                )

                HStack(spacing: 12) {
                    ForEach(PerformanceMetric.allCases, id: \.rawValue) { metric in
                        GraphLegendItem(title: metric.rawValue, color: metric.color)
                    }
                }
            } else {
                NoPerformanceMetricsView()
            }
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
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
