//
//  ApplicationCardView.swift
//  monitor_helper
//

import SwiftUI

struct ApplicationCardView: View {
    let application: ApplicationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HealthBadge(status: application.health)

                Spacer(minLength: 12)

                Text(MetricFormatter.relativeTime(application.lastUpdatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(application.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if application.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }

                Text(application.health.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(application.health.color)
            }

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

            HStack(spacing: 14) {
                Label("\(application.activeIncidentCount) active alarms", systemImage: "bell")
                Label(application.freshnessSummary, systemImage: application.isStale ? "clock.badge.exclamationmark" : "iphone")
            }
            .font(.caption)
            .foregroundStyle(application.isStale ? .orange : .secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(application.health.color.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    ApplicationCardView(application: MockMonitoringData.applications[0])
        .padding()
        .background(AppTheme.groupedBackground)
}
