//
//  PerformanceDetailView.swift
//  monitor_helper
//

import SwiftUI

struct PerformanceDetailView: View {
    let application: ApplicationSnapshot
    var chartCacheRevision = 0
    var chartStateProvider: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) -> MetricChartLoadState = { _, _, _ in .empty }
    var loadMetricChart: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) async -> Void = { _, _, _ in }

    @State private var selectedTimeRange: MonitoringTimeRange = .oneHour
    @State private var selectedMetric: PerformanceMetric = .averageResponseTime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Metric Window")
                        .font(.headline)

                    Spacer()

                    TimeRangePicker(selection: $selectedTimeRange)
                }

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(PerformanceMetric.allCases, id: \.self) { metric in
                        Text(metric.shortTitle)
                            .tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryTileView(
                        title: "Average Response Time",
                        value: MetricFormatter.responseTime(application.averageResponseTimeMs),
                        symbolName: "timer",
                        tint: application.health.color
                    )

                    SummaryTileView(
                        title: "Calls per Minute",
                        value: MetricFormatter.callsPerMinute(application.callsPerMinute),
                        symbolName: "arrow.left.arrow.right"
                    )

                    SummaryTileView(
                        title: "Errors per Minute",
                        value: MetricFormatter.errorsPerMinute(application.errorsPerMinute),
                        symbolName: "xmark.octagon",
                        tint: application.health == .critical ? .red : .orange
                    )

                    SummaryTileView(
                        title: "Error Percentage",
                        value: MetricFormatter.percentage(application.errorPercentage),
                        symbolName: "percent"
                    )
                }

                PerformanceSignalCard(
                    application: application,
                    selectedTimeRange: selectedTimeRange,
                    selectedMetric: selectedMetric,
                    chartState: chartStateProvider(application, selectedMetric, selectedTimeRange),
                    loadChart: {
                        await loadMetricChart(application, selectedMetric, selectedTimeRange)
                    }
                )
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: PerformanceChartTaskID(applicationID: application.id, metric: selectedMetric, range: selectedTimeRange, revision: chartCacheRevision)) {
            await loadMetricChart(application, selectedMetric, selectedTimeRange)
        }
    }
}

private struct PerformanceChartTaskID: Hashable {
    let applicationID: UUID
    let metric: PerformanceMetric
    let range: MonitoringTimeRange
    let revision: Int
}

#Preview {
    NavigationStack {
        PerformanceDetailView(application: MockMonitoringData.applications[0])
    }
}
