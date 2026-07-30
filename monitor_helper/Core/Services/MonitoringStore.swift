//
//  MonitoringStore.swift
//  monitor_helper
//

import Foundation
import Observation

@MainActor
@Observable
final class MonitoringStore {
    private var cachedApplications: [ApplicationSnapshot] = MockMonitoringData.applications

    private(set) var applications: [ApplicationSnapshot] = MockMonitoringData.applications
    private(set) var isRefreshing = false
    private(set) var lastLoadedAt: Date?
    var selectedTimeRange: MonitoringTimeRange = .oneHour

    func bootstrap() async {
        guard lastLoadedAt == nil else { return }
        applications = cachedApplications
        lastLoadedAt = Date.now
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // Keep the current snapshot visible while future Supabase refreshes run.
        try? await Task.sleep(for: .milliseconds(250))

        cachedApplications = MockMonitoringData.applications
        applications = cachedApplications
        lastLoadedAt = Date.now
    }
}
