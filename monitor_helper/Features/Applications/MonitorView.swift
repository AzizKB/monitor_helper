//
//  MonitorView.swift
//  monitor_helper
//

import SwiftUI

@MainActor
struct MonitorView: View {
    let applications: [ApplicationSnapshot]
    @Binding var selectedTimeRange: MonitoringTimeRange
    let isUsingLiveData: Bool
    let isRefreshing: Bool
    let errorMessage: String?
    let refresh: () async -> Void
    let nodesProvider: (ApplicationSnapshot) -> [NodeSnapshot]
    let loadNodes: (ApplicationSnapshot) async -> [NodeSnapshot]
    let incidentsProvider: (ApplicationSnapshot) -> [IncidentSnapshot]
    let loadIncidents: (ApplicationSnapshot) async -> [IncidentSnapshot]
    var chartCacheRevision = 0
    var chartStateProvider: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) -> MetricChartLoadState = { _, _, _ in .empty }
    var loadMetricChart: (ApplicationSnapshot, PerformanceMetric, MonitoringTimeRange) async -> Void = { _, _, _ in }

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

    private var attentionCount: Int {
        applications.filter { $0.health == .critical || $0.health == .warning }.count
    }

    private var lastSuccessfulSyncAt: Date? {
        applications.compactMap(\.lastSuccessfulSyncAt).max()
    }

    private var staleMetricApplications: [ApplicationSnapshot] {
        applications.filter { $0.isStale && $0.hasApplicationMetrics }
    }

    private var staleMetricApplicationCount: Int {
        staleMetricApplications.count
    }

    private var oldestStaleMetricAgeMinutes: Int? {
        staleMetricApplications
            .compactMap(\.dataAgeMinutes)
            .max()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fleetSummary
                dataSourceBanner

                Text("Applications")
                    .font(.headline)

                LazyVStack(spacing: 12) {
                    ForEach(sortedApplications) { application in
                        NavigationLink(value: application) {
                            ApplicationCardView(application: application)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Monitor")
        .refreshable {
            await refresh()
        }
        .navigationDestination(for: ApplicationSnapshot.self) { application in
            ApplicationOverviewView(
                application: application,
                nodesProvider: nodesProvider,
                loadNodes: loadNodes,
                incidentsProvider: incidentsProvider,
                loadIncidents: loadIncidents,
                chartCacheRevision: chartCacheRevision,
                chartStateProvider: chartStateProvider,
                loadMetricChart: loadMetricChart
            )
        }
    }

    private var fleetSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Application Monitoring")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Label(
                        isRefreshing ? "Refreshing..." : "\(selectedTimeRange.displayName) • Synced \(MetricFormatter.relativeTime(lastSuccessfulSyncAt))",
                        systemImage: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HealthBadge(status: attentionCount == 0 ? .healthy : .warning)
                    TimeRangePicker(selection: $selectedTimeRange)
                }
            }

            HStack(spacing: 10) {
                StatusCountPill(status: .critical, count: count(.critical))
                StatusCountPill(status: .warning, count: count(.warning))
                StatusCountPill(status: .healthy, count: count(.healthy))
                StatusCountPill(status: .noData, count: count(.noData))
            }
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private func count(_ status: HealthStatus) -> Int {
        applications.filter { $0.health == status }.count
    }

    private var dataSourceBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: dataSourceSymbol)
                    .foregroundStyle(dataSourceColor)

                Text(dataSourceTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(applications.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isUsingLiveData, staleMetricApplicationCount > 0 {
                Text(staleSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isRefreshing && !isUsingLiveData {
                Text("Loading the latest monitoring snapshot from Supabase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage, !isUsingLiveData {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(dataSourceColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var dataSourceTitle: String {
        if isUsingLiveData {
            if staleMetricApplicationCount > 0 {
                return "Supabase Live • Stale Snapshot"
            }

            return isRefreshing ? "Refreshing Supabase" : "Supabase Live"
        }

        if let errorMessage, !errorMessage.isEmpty {
            return "Live Data Unavailable"
        }

        return isRefreshing ? "Loading Supabase" : "Mock Data"
    }

    private var dataSourceSymbol: String {
        if isUsingLiveData {
            if staleMetricApplicationCount > 0 {
                return "clock.badge.exclamationmark"
            }

            return "checkmark.icloud.fill"
        }

        return isRefreshing ? "icloud.and.arrow.down.fill" : "exclamationmark.icloud.fill"
    }

    private var dataSourceColor: Color {
        if isUsingLiveData {
            if staleMetricApplicationCount > 0 {
                return .orange
            }

            return .green
        }

        return isRefreshing ? .blue : .orange
    }

    private var staleSummaryText: String {
        if let oldestStaleMetricAgeMinutes {
            return "\(staleMetricApplicationCount) apps have metric data older than 30 minutes. Oldest snapshot: \(oldestStaleMetricAgeMinutes)m."
        }

        return "\(staleMetricApplicationCount) apps have metric data older than 30 minutes."
    }
}

private struct StatusCountPill: View {
    let status: HealthStatus
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)

            Text(status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(status.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        MonitorView(
            applications: MockMonitoringData.applications,
            selectedTimeRange: .constant(.oneHour),
            isUsingLiveData: false,
            isRefreshing: false,
            errorMessage: nil,
            refresh: {},
            nodesProvider: { _ in [] },
            loadNodes: { _ in [] },
            incidentsProvider: { _ in [] },
            loadIncidents: { _ in [] }
        )
    }
}
