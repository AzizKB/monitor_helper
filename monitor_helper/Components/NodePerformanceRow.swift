//
//  NodePerformanceRow.swift
//  monitor_helper
//

import SwiftUI

struct NodePerformanceRow: View {
    let node: NodeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.nodeName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(node.tierName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HealthBadge(status: node.health)
            }

            HStack(spacing: 12) {
                MetricValueView(
                    title: "CPU",
                    value: MetricFormatter.infrastructurePercentage(node.cpuPercent),
                    symbolName: "cpu"
                )

                MetricValueView(
                    title: "Memory",
                    value: MetricFormatter.infrastructurePercentage(node.memoryPercent),
                    symbolName: "memorychip"
                )

                MetricValueView(
                    title: "Availability",
                    value: MetricFormatter.infrastructurePercentage(node.availabilityPercent),
                    symbolName: "antenna.radiowaves.left.and.right"
                )
            }
        }
        .padding(14)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(node.health.color.opacity(0.22), lineWidth: 1)
        )
    }
}

#Preview {
    NodePerformanceRow(node: MockMonitoringData.nodes(for: MockMonitoringData.applications[0])[0])
        .padding()
        .background(AppTheme.groupedBackground)
}
