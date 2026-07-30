//
//  MonitorView.swift
//  monitor_helper
//

import SwiftUI

struct MonitorView: View {
    let applications: [ApplicationSnapshot]
    @Binding var selectedTimeRange: MonitoringTimeRange
    let isRefreshing: Bool
    let refresh: () async -> Void

    private var sortedApplications: [ApplicationSnapshot] {
        applications.sorted {
            if $0.health.sortPriority == $1.health.sortPriority {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            return $0.health.sortPriority < $1.health.sortPriority
        }
    }

    private var attentionCount: Int {
        applications.filter { $0.health == .critical || $0.health == .warning }.count
    }

    private var lastUpdatedAt: Date? {
        applications.compactMap(\.lastUpdatedAt).max()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fleetSummary

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
            ApplicationOverviewView(application: application)
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
                        isRefreshing ? "Refreshing..." : "\(selectedTimeRange.displayName) • Updated \(MetricFormatter.relativeTime(lastUpdatedAt))",
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
            isRefreshing: false,
            refresh: {}
        )
    }
}
