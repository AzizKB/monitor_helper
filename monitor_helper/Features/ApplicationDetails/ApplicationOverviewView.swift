//
//  ApplicationOverviewView.swift
//  monitor_helper
//

import SwiftUI

@MainActor
struct ApplicationOverviewView: View {
    let application: ApplicationSnapshot
    var nodesProvider: (ApplicationSnapshot) -> [NodeSnapshot] = MockMonitoringData.nodes(for:)
    var loadNodes: (ApplicationSnapshot) async -> [NodeSnapshot] = { application in MockMonitoringData.nodes(for: application) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                overviewCards
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(application.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthBadge(status: application.health)

            Text("Updated \(MetricFormatter.relativeTime(application.lastUpdatedAt))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(application.nodeSummary, systemImage: "server.rack")
                Label(application.tierSummary, systemImage: "square.stack.3d.up")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewCards: some View {
        VStack(spacing: 10) {
            NavigationLink {
                PerformanceDetailView(application: application)
            } label: {
                OverviewRouteRow(
                    title: "Performance",
                    subtitle: "Average Response Time \(MetricFormatter.responseTime(application.averageResponseTimeMs)) • Calls per Minute \(MetricFormatter.callsPerMinute(application.callsPerMinute)) • Errors per Minute \(MetricFormatter.errorsPerMinute(application.errorsPerMinute))",
                    symbolName: "waveform.path.ecg",
                    status: application.health
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                InfrastructureDetailView(
                    application: application,
                    initialNodes: nodesProvider(application),
                    loadNodes: { await loadNodes(application) }
                )
            } label: {
                OverviewRouteRow(
                    title: "Infrastructure",
                    subtitle: "\(application.infrastructureSummary) • CPU \(MetricFormatter.infrastructurePercentage(application.worstCpuPercent)) • Memory \(MetricFormatter.infrastructurePercentage(application.worstMemoryPercent))",
                    symbolName: "server.rack",
                    status: application.infrastructureHealth
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                IncidentsDetailView(application: application)
            } label: {
                OverviewRouteRow(
                    title: "Incidents",
                    subtitle: "\(application.activeIncidentCount) active alarms from AppDynamics health rules",
                    symbolName: "bell.badge",
                    status: application.activeIncidentCount > 0 ? application.health : .healthy
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                EventsDetailView(application: application)
            } label: {
                OverviewRouteRow(
                    title: "Events",
                    subtitle: "Recent AppDynamics events and operational timeline",
                    symbolName: "clock.arrow.circlepath",
                    status: .healthy
                )
            }
            .buttonStyle(.plain)

            OverviewRouteRow(
                title: "Monitoring Freshness",
                subtitle: "Last mobile data point \(MetricFormatter.relativeTime(application.lastUpdatedAt))",
                symbolName: "arrow.clockwise.circle",
                status: application.lastUpdatedAt == nil ? .noData : .healthy
            )
        }
    }
}

private struct OverviewRouteRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(status.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ApplicationOverviewView(application: MockMonitoringData.applications[0])
    }
}
