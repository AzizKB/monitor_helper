//
//  MonitorTabView.swift
//  monitor_helper
//

import SwiftUI

struct MonitorTabView: View {
    @Bindable var store: MonitoringStore

    var body: some View {
        TabView {
            NavigationStack {
                MonitorView(
                    applications: store.applications,
                    selectedTimeRange: $store.selectedTimeRange,
                    isUsingLiveData: store.isUsingLiveData,
                    isRefreshing: store.isRefreshing,
                    errorMessage: store.errorMessage,
                    refresh: store.refresh,
                    nodesProvider: store.nodes(for:),
                    loadNodes: store.loadNodes(for:),
                    incidentsProvider: store.incidents(for:),
                    loadIncidents: store.loadIncidents(for:)
                )
            }
            .tabItem {
                Label("Monitor", systemImage: "eye")
            }

            NavigationStack {
                DashboardView(
                    applications: store.applications,
                    selectedTimeRange: $store.selectedTimeRange,
                    isUsingLiveData: store.isUsingLiveData,
                    isRefreshing: store.isRefreshing,
                    errorMessage: store.errorMessage,
                    refresh: store.refresh,
                    nodesProvider: store.nodes(for:),
                    loadNodes: store.loadNodes(for:)
                )
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SettingsView(
                    isUsingLiveData: store.isUsingLiveData,
                    isRefreshing: store.isRefreshing,
                    selectedTimeRange: store.selectedTimeRange,
                    lastLoadedAt: store.lastLoadedAt,
                    errorMessage: store.errorMessage,
                    signOut: store.signOut
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: store.selectedTimeRange) { _, _ in
            Task {
                await store.refreshForSelectedTimeRange()
            }
        }
    }
}

#Preview {
    MonitorTabView(store: MonitoringStore())
}
