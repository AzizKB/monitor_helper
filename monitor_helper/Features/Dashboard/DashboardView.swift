//
//  DashboardView.swift
//  monitor_helper
//

import SwiftUI

@MainActor
struct DashboardView: View {
    let applications: [ApplicationSnapshot]
    @Binding var selectedTimeRange: MonitoringTimeRange
    let isUsingLiveData: Bool
    let isRefreshing: Bool
    let errorMessage: String?
    let refresh: () async -> Void
    let nodesProvider: (ApplicationSnapshot) -> [NodeSnapshot]
    let loadNodes: (ApplicationSnapshot) async -> [NodeSnapshot]
    var chartCacheRevision = 0
    var chartStateProvider: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) -> MetricChartLoadState = { _, _, _ in .empty }
    var loadMetricChart: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) async -> Void = { _, _, _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                NavigationLink {
                    ApplicationPerformanceDashboardView(
                        applications: applications,
                        selectedTimeRange: selectedTimeRange,
                        chartCacheRevision: chartCacheRevision,
                        chartStateProvider: chartStateProvider,
                        loadMetricChart: loadMetricChart
                    )
                } label: {
                    DashboardRouteCard(
                        title: "Application Performance",
                        subtitle: "One compact performance signal for every monitored application",
                        symbolName: "waveform.path.ecg",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    InfrastructureHealthDashboardView(
                        applications: applications,
                        nodesProvider: nodesProvider,
                        loadNodes: loadNodes
                    )
                } label: {
                    DashboardRouteCard(
                        title: "Infrastructure Health",
                        subtitle: "Select one application and inspect node, tier, CPU, memory and availability state",
                        symbolName: "server.rack",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Dashboard")
        .refreshable {
            await refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Visual Monitoring")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                TimeRangePicker(selection: $selectedTimeRange)
            }

            Text("Use dashboards when you want to observe trends instead of inspecting one application from Monitor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(
                "\(dataSourceTitle) • \(applications.count) apps",
                systemImage: dataSourceSymbol
            )
            .font(.caption)
            .foregroundStyle(dataSourceColor)

            if isRefreshing && !isUsingLiveData {
                Text("Loading the latest monitoring snapshot from Supabase.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let errorMessage, !isUsingLiveData {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isRefreshing {
                Label("Refreshing cached monitoring snapshot", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dataSourceTitle: String {
        if isUsingLiveData {
            return isRefreshing ? "Refreshing Supabase" : "Supabase Live"
        }

        if let errorMessage, !errorMessage.isEmpty {
            return "Live Data Unavailable"
        }

        return isRefreshing ? "Loading Supabase" : "Mock Data"
    }

    private var dataSourceSymbol: String {
        if isUsingLiveData {
            return "checkmark.icloud.fill"
        }

        return isRefreshing ? "icloud.and.arrow.down.fill" : "exclamationmark.icloud.fill"
    }

    private var dataSourceColor: Color {
        if isUsingLiveData {
            return .green
        }

        return isRefreshing ? .blue : .orange
    }
}

private struct DashboardRouteCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        DashboardView(
            applications: MockMonitoringData.applications,
            selectedTimeRange: .constant(.oneHour),
            isUsingLiveData: false,
            isRefreshing: false,
            errorMessage: nil,
            refresh: {},
            nodesProvider: { _ in [] },
            loadNodes: { _ in [] }
        )
    }
}
