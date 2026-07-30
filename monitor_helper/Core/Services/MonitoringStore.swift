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
    private var cachedApplications: [ApplicationSnapshot] = MockMonitoringData.applications
    private var nodeCache: [UUID: [NodeSnapshot]] = [:]

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
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        isUsingLiveData = false
        nodeCache.removeAll()
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
            let dtos = try await supabaseClient.fetchMonitorApplications(accessToken: session.accessToken)
            let snapshots = dtos.map(SupabaseModelMapper.application(from:))
            applications = snapshots
            cachedApplications = snapshots
            isUsingLiveData = true
            lastLoadedAt = Date.now
        } catch {
            isUsingLiveData = false
            applications = cachedApplications
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            return nodes(for: application)
        }
    }
}
