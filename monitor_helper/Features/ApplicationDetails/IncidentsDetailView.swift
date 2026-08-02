//
//  IncidentsDetailView.swift
//  monitor_helper
//

import SwiftUI

struct IncidentsDetailView: View {
    let application: ApplicationSnapshot
    let initialIncidents: [IncidentSnapshot]
    let loadIncidents: () async -> [IncidentSnapshot]

    @State private var incidents: [IncidentSnapshot]
    @State private var isLoading = false

    init(
        application: ApplicationSnapshot,
        initialIncidents: [IncidentSnapshot] = [],
        loadIncidents: @escaping () async -> [IncidentSnapshot] = { [] }
    ) {
        self.application = application
        self.initialIncidents = initialIncidents
        self.loadIncidents = loadIncidents
        _incidents = State(initialValue: initialIncidents)
    }

    var body: some View {
        List {
            Section {
                SettingsLikeMetricRow(title: "Active Alarms", value: "\(application.activeIncidentCount)", symbolName: "bell.badge")
                SettingsLikeMetricRow(title: "Application Status", value: application.health.rawValue, symbolName: application.health.symbolName)
            }

            Section {
                if isLoading && incidents.isEmpty {
                    ProgressView("Loading active alarms")
                } else if incidents.isEmpty {
                    ContentUnavailableView(
                        "No Active Alarms",
                        systemImage: "checkmark.circle",
                        description: Text("Supabase has no open AppDynamics health-rule violations for this application.")
                    )
                } else {
                    ForEach(incidents) { incident in
                        NavigationLink {
                            IncidentFullDetailView(incident: incident)
                        } label: {
                            IncidentRow(incident: incident)
                        }
                    }
                }
            }
        }
        .navigationTitle("Incidents")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshIncidents()
        }
        .refreshable {
            await refreshIncidents()
        }
    }

    private func refreshIncidents() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        incidents = await loadIncidents()
    }
}

private struct IncidentRow: View {
    let incident: IncidentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: incident.severity.symbolName)
                    .foregroundStyle(incident.severity.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(incident.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("\(incident.severity.rawValue) • \(incident.status)")
                        .font(.caption)
                        .foregroundStyle(incident.severity.color)
                }

                Spacer()

                Text(incident.durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = incident.cleanDescription {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text("Started \(MetricFormatter.relativeTime(incident.startedAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct IncidentFullDetailView: View {
    let incident: IncidentSnapshot

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: incident.severity.symbolName)
                            .foregroundStyle(incident.severity.color)
                            .font(.title2)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(incident.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(incident.severity.rawValue) • \(incident.status)")
                                .font(.subheadline)
                                .foregroundStyle(incident.severity.color)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Alarm Details") {
                SettingsLikeMetricRow(title: "Severity", value: incident.severity.rawValue, symbolName: incident.severity.symbolName)
                SettingsLikeMetricRow(title: "Status", value: incident.status, symbolName: "circle.dashed")
                SettingsLikeMetricRow(title: "Duration", value: incident.durationText, symbolName: "clock")
                SettingsLikeMetricRow(title: "Started", value: startedText, symbolName: "calendar")
            }

            Section("Description") {
                Text(incident.cleanDescription ?? "No description was provided by AppDynamics.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("Alarm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var startedText: String {
        guard let startedAt = incident.startedAt else { return "--" }

        return startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        IncidentsDetailView(application: MockMonitoringData.applications[0])
    }
}
