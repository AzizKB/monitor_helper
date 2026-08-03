//
//  SettingsView.swift
//  monitor_helper
//

import SwiftUI

struct SettingsView: View {
    var isUsingLiveData = false
    var isRefreshing = false
    var selectedTimeRange: MonitoringTimeRange = .oneHour
    var lastLoadedAt: Date?
    var errorMessage: String?
    var signOut: (() -> Void)?

    var body: some View {
        List {
            Section {
                connectionStatusCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Monitoring") {
                SettingsRow(title: "Auto Refresh", value: "Every 5 minutes", symbolName: "arrow.clockwise")
                SettingsRow(title: "Foreground Refresh", value: "After 1 minute", symbolName: "iphone.radiowaves.left.and.right")
                SettingsRow(title: "Selected Range", value: selectedTimeRange.displayName, symbolName: "chart.xyaxis.line")
                SettingsRow(title: "Data Retention", value: "48 hours", symbolName: "clock")
            }

            Section("Security") {
                SettingsRow(title: "Access Mode", value: "Read only", symbolName: "lock")
                SettingsRow(title: "Mobile Source", value: "Supabase API", symbolName: "externaldrive.connected.to.line.below")
                SettingsRow(title: "AppDynamics", value: "Not exposed", symbolName: "network.slash")
            }

            if let signOut {
                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            Section("About") {
                SettingsRow(title: "App Name", value: "monitor_helper", symbolName: "app")
                SettingsRow(title: "Version", value: "1.0", symbolName: "number")
                SettingsRow(title: "Platform", value: "iPhone", symbolName: "iphone")
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
    }

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sourceSymbol)
                    .font(.title2)
                    .foregroundStyle(sourceColor)
                    .frame(width: 40, height: 40)
                    .background(sourceColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceTitle)
                        .font(.headline)

                    Text(sourceSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if let errorMessage, !isUsingLiveData, !isRefreshing {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 16) {
                SettingsStatusMetric(title: "Last Update", value: MetricFormatter.relativeTime(lastLoadedAt))
                SettingsStatusMetric(title: "Refresh", value: isRefreshing ? "Running" : "Ready")
            }
        }
        .padding(16)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var sourceTitle: String {
        if isUsingLiveData {
            return isRefreshing ? "Refreshing Supabase" : "Supabase Live"
        }

        if let errorMessage, !errorMessage.isEmpty {
            return "Live Data Unavailable"
        }

        return isRefreshing ? "Loading Supabase" : "Not Connected"
    }

    private var sourceSubtitle: String {
        if isUsingLiveData {
            return "Monitoring data is loaded from the authenticated mobile API."
        }

        if isRefreshing {
            return "The app is fetching the latest monitoring snapshot."
        }

        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        return "Sign in and load a Supabase monitoring snapshot."
    }

    private var sourceSymbol: String {
        if isUsingLiveData {
            return "checkmark.icloud.fill"
        }

        return isRefreshing ? "icloud.and.arrow.down.fill" : "exclamationmark.icloud.fill"
    }

    private var sourceColor: Color {
        if isUsingLiveData {
            return .green
        }

        return isRefreshing ? .blue : .orange
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
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsStatusMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
