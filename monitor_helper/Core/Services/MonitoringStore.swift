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
    private let sessionStore = SupabaseSessionStore()
    private var cachedApplications: [ApplicationSnapshot] = []
    private var applicationCacheByRange: [MonitoringTimeRange: [ApplicationSnapshot]] = [:]
    private var nodeCache: [UUID: [NodeSnapshot]] = [:]
    private var incidentCache: [UUID: [IncidentSnapshot]] = [:]
    private var hasLoadedLiveData = false
    private var lastRealtimeSyncKey: String?

    private(set) var session: StoredSupabaseSession?
    private(set) var applications: [ApplicationSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var isRestoringSession = false
    private(set) var lastLoadedAt: Date?
    private(set) var errorMessage: String?
    private(set) var isUsingLiveData = false
    private(set) var dataState: MonitoringDataState = .initial
    var selectedTimeRange: MonitoringTimeRange = .oneHour

    var isAuthenticated: Bool {
        session != nil
    }

    func bootstrap() async {
        guard session == nil, !isRestoringSession else { return }

        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            guard let storedSession = try sessionStore.load() else {
                dataState = .initial
                return
            }

            session = storedSession

            if storedSession.isExpiringSoon(), storedSession.isRefreshable {
                try await refreshStoredSession()
            } else if storedSession.isExpiringSoon() {
                expireSession(message: "Your session expired. Please sign in again.")
            }
        } catch {
            expireSession(message: "Your saved session could not be restored. Please sign in again.")
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let authSession = try await supabaseClient.signIn(email: email, password: password)
            let storedSession = StoredSupabaseSession(authSession: authSession)
            try sessionStore.save(storedSession)
            session = storedSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? sessionStore.clear()
        session = nil
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        incidentCache.removeAll()
        applications = []
        cachedApplications = []
        lastLoadedAt = nil
        dataState = .initial
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        guard session != nil else {
            applications = cachedApplications
            lastLoadedAt = Date.now
            return
        }

        if !hasLoadedLiveData {
            dataState = .loading
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchMonitorApplications(
                    minutes: selectedTimeRange.minutes,
                    accessToken: accessToken
                )
            }
            let snapshots = dtos.map(SupabaseModelMapper.application(from:))
            applications = snapshots
            cachedApplications = snapshots
            applicationCacheByRange[selectedTimeRange] = snapshots
            isUsingLiveData = true
            hasLoadedLiveData = true
            lastLoadedAt = Date.now
            dataState = snapshots.isEmpty ? .empty : .live
            print("Supabase refresh succeeded: \(snapshots.count) applications for \(selectedTimeRange.displayName)")
        } catch {
            guard !Self.isCancellation(error) else {
                print("Supabase refresh cancelled")
                return
            }

            isUsingLiveData = hasLoadedLiveData
            applications = cachedApplications
            errorMessage = error.localizedDescription
            dataState = hasLoadedLiveData
                ? .cached(lastUpdated: lastLoadedAt ?? .now)
                : .failed(message: error.localizedDescription)
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
        nodeCache[application.id] ?? []
    }

    func loadNodes(for application: ApplicationSnapshot) async -> [NodeSnapshot] {
        guard session != nil else {
            return nodes(for: application)
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchNodes(
                    applicationID: application.id,
                    accessToken: accessToken
                )
            }
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
        guard session != nil else {
            return incidents(for: application)
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchIncidents(
                    applicationID: application.id,
                    limit: 50,
                    accessToken: accessToken
                )
            }
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

    private func authenticatedRequest<T>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        let accessToken = try await validAccessToken()

        do {
            return try await operation(accessToken)
        } catch SupabaseRESTError.requestFailed(401, _) {
            try await refreshStoredSession()

            guard let refreshedAccessToken = session?.accessToken else {
                throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
            }

            do {
                return try await operation(refreshedAccessToken)
            } catch SupabaseRESTError.requestFailed(401, _) {
                expireSession(message: "Your session expired. Please sign in again.")
                throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
            }
        }
    }

    private func validAccessToken() async throws -> String {
        guard let currentSession = session else {
            throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
        }

        if currentSession.isExpiringSoon() {
            try await refreshStoredSession()
        }

        guard let accessToken = session?.accessToken else {
            throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
        }

        return accessToken
    }

    private func refreshStoredSession() async throws {
        guard let currentSession = session, let refreshToken = currentSession.refreshToken else {
            expireSession(message: "Your session expired. Please sign in again.")
            throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
        }

        do {
            let refreshedAuthSession = try await supabaseClient.refreshSession(refreshToken: refreshToken)
            let refreshedSession = StoredSupabaseSession(authSession: refreshedAuthSession)
            let mergedSession = StoredSupabaseSession(
                accessToken: refreshedSession.accessToken,
                refreshToken: refreshedSession.refreshToken ?? currentSession.refreshToken,
                expiresAt: refreshedSession.expiresAt,
                userID: refreshedSession.userID ?? currentSession.userID,
                userEmail: refreshedSession.userEmail ?? currentSession.userEmail
            )

            try sessionStore.save(mergedSession)
            session = mergedSession
        } catch {
            expireSession(message: "Your session expired. Please sign in again.")
            throw error
        }
    }

    private func expireSession(message: String) {
        try? sessionStore.clear()
        session = nil
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        incidentCache.removeAll()
        applications = []
        cachedApplications = []
        lastLoadedAt = nil
        dataState = .failed(message: message)
        errorMessage = message
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
