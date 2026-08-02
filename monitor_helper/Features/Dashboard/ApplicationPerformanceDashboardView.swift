//
//  ApplicationPerformanceDashboardView.swift
//  monitor_helper
//

import Charts
import SwiftUI

struct ApplicationPerformanceDashboardView: View {
    let applications: [ApplicationSnapshot]
    let selectedTimeRange: MonitoringTimeRange

    private var sortedApplications: [ApplicationSnapshot] {
        applications.sorted {
            if $0.health.sortPriority == $1.health.sortPriority {
                if $0.hasApplicationMetrics != $1.hasApplicationMetrics {
                    return $0.hasApplicationMetrics
                }

                if $0.lastUpdatedAt != $1.lastUpdatedAt {
                    return ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast)
                }

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

    private var subtitle: String {
        selectedTimeRange.minutes <= 30
            ? "\(selectedTimeRange.displayName) current performance signal"
            : "\(selectedTimeRange.displayName) normalized performance signal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.displayName)
                        .font(.headline)

                    Text(subtitle)
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
            } else {
                NoPerformanceMetricsView()
            }

            CallErrorDonutView(application: application)

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

private struct CallErrorDonutView: View {
    let application: ApplicationSnapshot

    private var callsPerMinute: Double? {
        application.callsPerMinute
    }

    private var errorsPerMinute: Double? {
        application.errorsPerMinute
    }

    private var errorPercentage: Double? {
        if let errorPercentage = application.errorPercentage {
            return errorPercentage
        }

        guard let callsPerMinute, let errorsPerMinute, callsPerMinute > 0 else {
            return nil
        }

        return errorsPerMinute / callsPerMinute * 100
    }

    private var slices: [CallErrorSlice] {
        guard let callsPerMinute, let errorsPerMinute, callsPerMinute > 0 else {
            return []
        }

        let boundedErrors = min(max(errorsPerMinute, 0), callsPerMinute)
        let minimumVisibleErrorSlice = callsPerMinute * 0.03
        let chartErrors = boundedErrors > 0 ? max(boundedErrors, minimumVisibleErrorSlice) : 0
        let successfulCalls = max(callsPerMinute - chartErrors, 0)

        return [
            CallErrorSlice(name: "Successful Calls", value: successfulCalls, color: .green),
            CallErrorSlice(name: "Errors", value: chartErrors, color: .red)
        ].filter { $0.value > 0 }
    }

    var body: some View {
        HStack(spacing: 14) {
            chart

            VStack(alignment: .leading, spacing: 6) {
                Text("Calls vs Errors")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if callsPerMinute == nil || errorsPerMinute == nil {
                    Text("No call/error data for this range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if slices.isEmpty {
                    Text("No calls observed in this range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        LegendText(
                            title: "CPM",
                            value: MetricFormatter.callsPerMinute(callsPerMinute),
                            color: .green
                        )

                        LegendText(
                            title: "EPM",
                            value: MetricFormatter.errorsPerMinute(errorsPerMinute),
                            color: .red
                        )

                        LegendText(
                            title: "Error %",
                            value: MetricFormatter.percentage(errorPercentage),
                            color: .orange
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var chart: some View {
        if slices.isEmpty {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.18), lineWidth: 12)

                Text("--")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 68, height: 68)
        } else {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Value", slice.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.2
                )
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: 68, height: 68)
            .overlay {
                Text(MetricFormatter.percentage(errorPercentage))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
    }
}

private struct CallErrorSlice: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

private struct LegendText: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
