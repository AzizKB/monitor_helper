//
//  SettingsView.swift
//  monitor_helper
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("Monitoring") {
                SettingsRow(title: "Refresh Interval", value: "15 minutes", symbolName: "arrow.clockwise")
                SettingsRow(title: "Default Chart Range", value: "1 hour", symbolName: "chart.xyaxis.line")
                SettingsRow(title: "Data Retention", value: "48 hours", symbolName: "clock")
            }

            Section("Access") {
                SettingsRow(title: "Mode", value: "Read only", symbolName: "lock")
                SettingsRow(title: "Source", value: "Supabase", symbolName: "externaldrive.connected.to.line.below")
            }

            Section("About") {
                SettingsRow(title: "App Name", value: "monitor_helper", symbolName: "app")
                SettingsRow(title: "Version", value: "1.0", symbolName: "number")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
