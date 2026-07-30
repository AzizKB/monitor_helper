//
//  IncidentsDetailView.swift
//  monitor_helper
//

import SwiftUI

struct IncidentsDetailView: View {
    let application: ApplicationSnapshot

    var body: some View {
        List {
            Section {
                SettingsLikeMetricRow(title: "Active Alarms", value: "\(application.activeIncidentCount)", symbolName: "bell.badge")
                SettingsLikeMetricRow(title: "Application Status", value: application.health.rawValue, symbolName: application.health.symbolName)
            }

            Section {
                Label("Incident details will use active AppDynamics health-rule violations from Supabase.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Incidents")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        IncidentsDetailView(application: MockMonitoringData.applications[0])
    }
}
