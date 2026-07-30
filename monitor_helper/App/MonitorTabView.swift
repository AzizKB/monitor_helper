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
                    loadNodes: store.loadNodes(for:)
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
                    signOut: store.signOut
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(AppTheme.accent)
    }
}

#Preview {
    MonitorTabView(store: MonitoringStore())
}
