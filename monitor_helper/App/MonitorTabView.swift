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
                    isRefreshing: store.isRefreshing,
                    refresh: store.refresh
                )
            }
            .tabItem {
                Label("Monitor", systemImage: "eye")
            }

            NavigationStack {
                DashboardView(
                    applications: store.applications,
                    selectedTimeRange: $store.selectedTimeRange,
                    isRefreshing: store.isRefreshing,
                    refresh: store.refresh
                )
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SettingsView()
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
