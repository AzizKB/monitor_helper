//
//  InfrastructureHealthDashboardView.swift
//  monitor_helper
//

import SwiftUI

@MainActor
struct InfrastructureHealthDashboardView: View {
    let applications: [ApplicationSnapshot]
    let nodesProvider: (ApplicationSnapshot) -> [NodeSnapshot]
    let loadNodes: (ApplicationSnapshot) async -> [NodeSnapshot]

    @State private var selectedApplicationID: UUID?

    private var selectedApplication: ApplicationSnapshot? {
        let selectedID = selectedApplicationID ?? applications.first?.id
        return applications.first { $0.id == selectedID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Application", selection: bindingSelection) {
                    ForEach(applications) { application in
                        Text(application.displayName)
                            .tag(Optional(application.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedApplication {
                    infrastructureSummary(for: selectedApplication)
                    nodeSection(for: selectedApplication)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Infra Health")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedApplication?.id) {
            if let selectedApplication {
                _ = await loadNodes(selectedApplication)
            }
        }
    }

    private var bindingSelection: Binding<UUID?> {
        Binding(
            get: { selectedApplicationID ?? applications.first?.id },
            set: { selectedApplicationID = $0 }
        )
    }

    private func infrastructureSummary(for application: ApplicationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(application.infrastructureSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HealthBadge(status: application.infrastructureHealth)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryTileView(
                    title: "Worst CPU",
                    value: MetricFormatter.infrastructurePercentage(application.worstCpuPercent),
                    symbolName: "cpu",
                    tint: cpuTint(application.worstCpuPercent)
                )

                SummaryTileView(
                    title: "Worst Memory",
                    value: MetricFormatter.infrastructurePercentage(application.worstMemoryPercent),
                    symbolName: "memorychip",
                    tint: memoryTint(application.worstMemoryPercent)
                )

                SummaryTileView(
                    title: "Availability",
                    value: MetricFormatter.infrastructurePercentage(application.availabilityPercent),
                    symbolName: "antenna.radiowaves.left.and.right",
                    tint: application.infrastructureHealth.color
                )

                SummaryTileView(
                    title: "Nodes Reporting",
                    value: application.nodeSummary,
                    symbolName: "server.rack",
                    tint: application.infrastructureHealth.color
                )
            }
        }
    }

    private func nodeSection(for application: ApplicationSnapshot) -> some View {
        let nodes = nodesProvider(application)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Node Performance")
                .font(.headline)

            if nodes.isEmpty {
                ContentUnavailableView(
                    "No Node Data",
                    systemImage: "server.rack",
                    description: Text("Node metrics will appear when the collector receives infrastructure data for this application.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(nodes) { node in
                    NodePerformanceRow(node: node)
                }
            }
        }
    }

    private func cpuTint(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 95 { return .red }
        if value >= 75 { return .orange }
        return .green
    }

    private func memoryTint(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 95 { return .red }
        if value >= 75 { return .orange }
        return .green
    }
}

#Preview {
    NavigationStack {
        InfrastructureHealthDashboardView(
            applications: MockMonitoringData.applications,
            nodesProvider: { _ in [] },
            loadNodes: { _ in [] }
        )
    }
}
