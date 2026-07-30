//
//  ApplicationPerformanceDashboardView.swift
//  monitor_helper
//

import SwiftUI

struct ApplicationPerformanceDashboardView: View {
    let applications: [ApplicationSnapshot]
    let selectedTimeRange: MonitoringTimeRange

    private var sortedApplications: [ApplicationSnapshot] {
        applications.sorted {
            if $0.health.sortPriority == $1.health.sortPriority {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            return $0.health.sortPriority < $1.health.sortPriority
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sortedApplications) { application in
                    PerformanceDashboardPanel(
                        application: application,
                        selectedTimeRange: selectedTimeRange
                    )
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("App Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PerformanceDashboardPanel: View {
    let application: ApplicationSnapshot
    let selectedTimeRange: MonitoringTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.displayName)
                        .font(.headline)

                    Text("\(selectedTimeRange.displayName) normalized performance signal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HealthBadge(status: application.health)
            }

            PerformanceLineGraphView(
                application: application,
                selectedTimeRange: selectedTimeRange
            )

            HStack(spacing: 12) {
                MetricValueView(
                    title: "Average Response Time",
                    value: MetricFormatter.responseTime(application.averageResponseTimeMs),
                    symbolName: "timer"
                )
                MetricValueView(
                    title: "Calls per Minute",
                    value: MetricFormatter.callsPerMinute(application.callsPerMinute),
                    symbolName: "arrow.left.arrow.right"
                )
                MetricValueView(
                    title: "Errors per Minute",
                    value: MetricFormatter.errorsPerMinute(application.errorsPerMinute),
                    symbolName: "xmark.octagon"
                )
            }
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ApplicationPerformanceDashboardView(
            applications: MockMonitoringData.applications,
            selectedTimeRange: .oneHour
        )
    }
}
