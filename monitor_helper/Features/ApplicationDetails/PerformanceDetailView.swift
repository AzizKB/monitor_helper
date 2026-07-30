//
//  PerformanceDetailView.swift
//  monitor_helper
//

import SwiftUI

struct PerformanceDetailView: View {
    let application: ApplicationSnapshot
    @State private var selectedTimeRange: MonitoringTimeRange = .oneHour

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Metric Window")
                        .font(.headline)

                    Spacer()

                    TimeRangePicker(selection: $selectedTimeRange)
                }

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
                    selectedTimeRange: selectedTimeRange
                )
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PerformanceDetailView(application: MockMonitoringData.applications[0])
    }
}
