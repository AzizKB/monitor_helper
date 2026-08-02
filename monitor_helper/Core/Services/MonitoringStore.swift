//
//  MonitoringStore.swift
//  monitor_helper
//

import Foundation
import Observation

@MainActor
@Observable
final class MonitoringStore {
    private let supabaseClient = SupabaseRESTClient()
    private let realtimeSyncListener = SupabaseRealtimeSyncListener()
    private var cachedApplications: [ApplicationSnapshot] = MockMonitoringData.applications
    private var applicationCacheByRange: [MonitoringTimeRange: [ApplicationSnapshot]] = [:]
    private var nodeCache: [UUID: [NodeSnapshot]] = [:]
    private var incidentCache: [UUID: [IncidentSnapshot]] = [:]
    private var hasLoadedLiveData = false
    private var lastRealtimeSyncKey: String?

    private(set) var session: SupabaseAuthSession?
    private(set) var applications: [ApplicationSnapshot] = MockMonitoringData.applications
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var lastLoadedAt: Date?
    private(set) var errorMessage: String?
    private(set) var isUsingLiveData = false
    var selectedTimeRange: MonitoringTimeRange = .oneHour

    var isAuthenticated: Bool {
        session != nil
    }

    func bootstrap() async {
        guard lastLoadedAt == nil else { return }
        applications = cachedApplications
        lastLoadedAt = Date.now
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let authSession = try await supabaseClient.signIn(email: email, password: password)
            session = authSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        incidentCache.removeAll()
        applications = MockMonitoringData.applications
        cachedApplications = MockMonitoringData.applications
        lastLoadedAt = Date.now
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        guard let session else {
            applications = cachedApplications
            lastLoadedAt = Date.now
            return
        }

        do {
            let dtos = try await supabaseClient.fetchMonitorApplications(
                minutes: selectedTimeRange.minutes,
                accessToken: session.accessToken
            )
            let snapshots = dtos.map(SupabaseModelMapper.application(from:))
            applications = snapshots
            cachedApplications = snapshots
            applicationCacheByRange[selectedTimeRange] = snapshots
            isUsingLiveData = true
            hasLoadedLiveData = true
            lastLoadedAt = Date.now
            print("Supabase refresh succeeded: \(snapshots.count) applications for \(selectedTimeRange.displayName)")
        } catch {
            guard !Self.isCancellation(error) else {
                print("Supabase refresh cancelled")
                return
            }

            isUsingLiveData = hasLoadedLiveData
            applications = cachedApplications
            errorMessage = error.localizedDescription
            print("Supabase refresh failed: \(error.localizedDescription)")
        }
    }

    func refreshForSelectedTimeRange() async {
        if let cachedRangeApplications = applicationCacheByRange[selectedTimeRange] {
            applications = cachedRangeApplications
            cachedApplications = cachedRangeApplications
        }

        await refresh()
    }

    func refreshIfNeeded(maxAge: TimeInterval = 60) async {
        guard isAuthenticated else { return }

        if let lastLoadedAt, Date.now.timeIntervalSince(lastLoadedAt) < maxAge {
            return
        }

        await refresh()
    }

    func listenForSyncCompletions() async {
        guard let session else { return }

        for await event in realtimeSyncListener.successfulSyncEvents(accessToken: session.accessToken) {
            guard isAuthenticated else { return }

            let syncKey = event.deduplicationKey
            guard syncKey != lastRealtimeSyncKey else { continue }
            lastRealtimeSyncKey = syncKey

            try? await Task.sleep(for: .seconds(1))
            await refresh()
            print("Supabase realtime sync refresh completed: \(syncKey)")
        }
    }

    func nodes(for application: ApplicationSnapshot) -> [NodeSnapshot] {
        nodeCache[application.id] ?? MockMonitoringData.nodes(for: application)
    }

    func loadNodes(for application: ApplicationSnapshot) async -> [NodeSnapshot] {
        guard let session else {
            return nodes(for: application)
        }

        do {
            let dtos = try await supabaseClient.fetchNodes(
                applicationID: application.id,
                accessToken: session.accessToken
            )
            let nodes = dtos.map(SupabaseModelMapper.node(from:))
            nodeCache[application.id] = nodes
            return nodes
        } catch {
            guard !Self.isCancellation(error) else {
                return nodes(for: application)
            }

            errorMessage = error.localizedDescription
            return nodes(for: application)
        }
    }

    func incidents(for application: ApplicationSnapshot) -> [IncidentSnapshot] {
        incidentCache[application.id] ?? []
    }

    func loadIncidents(for application: ApplicationSnapshot) async -> [IncidentSnapshot] {
        guard let session else {
            return incidents(for: application)
        }

        do {
            let dtos = try await supabaseClient.fetchIncidents(
                applicationID: application.id,
                limit: 50,
                accessToken: session.accessToken
            )
            let incidents = dtos.map(SupabaseModelMapper.incident(from:))
            incidentCache[application.id] = incidents
            return incidents
        } catch {
            guard !Self.isCancellation(error) else {
                return incidents(for: application)
            }

            errorMessage = error.localizedDescription
            return incidents(for: application)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        return (error as NSError).code == NSURLErrorCancelled
    }
}
