//
//  InfrastructureDetailView.swift
//  monitor_helper
//

import SwiftUI

struct InfrastructureDetailView: View {
    let application: ApplicationSnapshot

    private var nodes: [NodeSnapshot] {
        MockMonitoringData.nodes(for: application)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryTileView(
                        title: "Infrastructure Status",
                        value: application.infrastructureHealth.rawValue,
                        symbolName: application.infrastructureHealth.symbolName,
                        tint: application.infrastructureHealth.color
                    )

                    SummaryTileView(
                        title: "Nodes Reporting",
                        value: application.nodeSummary,
                        symbolName: "server.rack",
                        tint: application.infrastructureHealth.color
                    )

                    SummaryTileView(
                        title: "Worst CPU",
                        value: MetricFormatter.infrastructurePercentage(application.worstCpuPercent),
                        symbolName: "cpu",
                        tint: application.infrastructureHealth.color
                    )

                    SummaryTileView(
                        title: "Worst Memory",
                        value: MetricFormatter.infrastructurePercentage(application.worstMemoryPercent),
                        symbolName: "memorychip",
                        tint: application.infrastructureHealth.color
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Nodes")
                        .font(.headline)

                    if nodes.isEmpty {
                        ContentUnavailableView(
                            "No Node Data",
                            systemImage: "server.rack",
                            description: Text("Infrastructure details will appear when node metrics are available.")
                        )
                        .padding(.vertical, 12)
                    } else {
                        ForEach(nodes) { node in
                            NodePerformanceRow(node: node)
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("Infrastructure")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InfrastructureDetailView(application: MockMonitoringData.applications[0])
    }
}
