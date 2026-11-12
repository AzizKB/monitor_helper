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
    private var chartCache: [ChartCacheKey: MetricChartLoadState] = [:]
    private var hasLoadedLiveData = false
    private var lastRealtimeSyncKey: String?

    private(set) var session: StoredSupabaseSession?
    private(set) var applications: [ApplicationSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var isSigningUp = false
    private(set) var isCheckingAccess = false
    private(set) var isRestoringSession = false
    private(set) var lastLoadedAt: Date?
    private(set) var errorMessage: String?
    private(set) var signUpMessage: String?
    private(set) var accessStatus: MobileAccessStatus = .unknown
    private(set) var isUsingLiveData = false
    private(set) var dataState: MonitoringDataState = .initial
    private(set) var chartCacheRevision = 0
    var selectedTimeRange: MonitoringTimeRange = .oneHour

    var isAuthenticated: Bool {
        session != nil
    }

    var canAccessMonitoring: Bool {
        isAuthenticated && accessStatus.isApproved
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
                return
            }

            await refreshMobileAccessStatus()
        } catch {
            expireSession(message: "Your saved session could not be restored. Please sign in again.")
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        signUpMessage = nil
        defer { isSigningIn = false }

        do {
            let authSession = try await supabaseClient.signIn(email: email, password: password)
            let storedSession = StoredSupabaseSession(authSession: authSession)
            try sessionStore.save(storedSession)
            session = storedSession
            await refreshMobileAccessStatus()
        } catch {
            errorMessage = AuthenticationMessage.error(error, action: .signIn)
        }
    }

    @discardableResult
    func signUp(email: String, password: String) async -> Bool {
        guard !isSigningUp else { return false }

        isSigningUp = true
        errorMessage = nil
        signUpMessage = nil
        defer { isSigningUp = false }

        do {
            let response = try await supabaseClient.signUp(email: email, password: password)

            if let authSession = response.session {
                let storedSession = StoredSupabaseSession(authSession: authSession)
                try sessionStore.save(storedSession)
                session = storedSession
                await refreshMobileAccessStatus()
            }

            signUpMessage = "Account created. Confirm your email, then wait for admin approval."
            return true
        } catch {
            errorMessage = AuthenticationMessage.error(error, action: .signUp)
            return false
        }
    }

    func clearAuthenticationMessages() {
        errorMessage = nil
        signUpMessage = nil
    }

    func completeEmailVerification(_ authSession: SupabaseAuthSession) async {
        do {
            let storedSession = StoredSupabaseSession(authSession: authSession)
            try sessionStore.save(storedSession)
            session = storedSession
            await refreshMobileAccessStatus()
        } catch { errorMessage = "We couldn't save your session. Please sign in again." }
    }

    func refreshMobileAccessStatus() async {
        guard session != nil else {
            accessStatus = .unknown
            return
        }

        isCheckingAccess = true
        defer { isCheckingAccess = false }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchMobileAccessStatus(accessToken: accessToken)
            }

            accessStatus = dtos.first.map(SupabaseModelMapper.mobileAccess(from:)) ?? MobileAccessStatus(
                userID: nil,
                email: session?.userEmail,
                decision: .pending,
                role: nil,
                requestedAt: nil,
                approvedAt: nil
            )

            if accessStatus.isApproved {
                errorMessage = nil
            }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = AuthenticationMessage.error(error, action: .checkAccess)
            accessStatus = MobileAccessStatus(
                userID: nil,
                email: session?.userEmail,
                decision: .unknown,
                role: nil,
                requestedAt: nil,
                approvedAt: nil
            )
        }
    }

    func signOut() {
        try? sessionStore.clear()
        session = nil
        accessStatus = .unknown
        signUpMessage = nil
        errorMessage = nil
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        incidentCache.removeAll()
        chartCache.removeAll()
        applications = []
        cachedApplications = []
        lastLoadedAt = nil
        dataState = .initial
        chartCacheRevision += 1
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

        guard canAccessMonitoring else {
            applications = []
            cachedApplications = []
            isUsingLiveData = false
            hasLoadedLiveData = false
            dataState = .initial
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
            chartCache.removeAll()
            chartCacheRevision += 1
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
        guard canAccessMonitoring else { return }

        if let lastLoadedAt, Date.now.timeIntervalSince(lastLoadedAt) < maxAge {
            return
        }

        await refresh()
    }

    func chartState(
        for application: ApplicationSnapshot,
        metric: PerformanceMetric,
        range: MonitoringTimeRange
    ) -> MetricChartLoadState {
        chartCache[ChartCacheKey(applicationID: application.id, metric: metric, range: range)] ?? .initial
    }

    func loadMetricChart(
        for application: ApplicationSnapshot,
        metric: PerformanceMetric,
        range: MonitoringTimeRange
    ) async {
        let key = ChartCacheKey(applicationID: application.id, metric: metric, range: range)

        if case .loaded = chartCache[key] {
            return
        }

        if case .loading = chartCache[key] {
            return
        }

        guard application.hasApplicationMetrics else {
            chartCache[key] = .empty
            return
        }

        guard canAccessMonitoring else {
            chartCache[key] = .failed("Sign in to load live chart data.")
            return
        }

        chartCache[key] = .loading
        let revision = chartCacheRevision
        let requestedEnd = lastLoadedAt ?? .now

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchMetricChart(
                    applicationID: application.id,
                    metricKey: metric.metricKey,
                    minutes: range.minutes,
                    endAt: requestedEnd,
                    accessToken: accessToken
                )
            }
            let points = dtos.compactMap(SupabaseModelMapper.chartPoint(from:))
            guard revision == chartCacheRevision, canAccessMonitoring else { return }

            guard !points.isEmpty else {
                chartCache[key] = .empty
                return
            }

            guard let first = dtos.first,
                  let windowStart = SupabaseDateParser.date(from: first.windowStart),
                  let windowEnd = SupabaseDateParser.date(from: first.windowEnd),
                  windowStart < windowEnd,
                  first.bucketMinutes == range.chartIntervalMinutes else {
                chartCache[key] = .failed("Chart time range could not be verified. Please retry.")
                return
            }
            chartCache[key] = .loaded(MetricChartSeries(
                metric: metric,
                points: points,
                windowStart: windowStart,
                windowEnd: windowEnd,
                intervalMinutes: range.chartIntervalMinutes
            ))
        } catch {
            guard revision == chartCacheRevision, canAccessMonitoring else { return }
            guard !Self.isCancellation(error) else {
                chartCache[key] = .initial
                return
            }

            chartCache[key] = .failed(error.localizedDescription)
        }
    }

    func listenForSyncCompletions() async {
        guard canAccessMonitoring else { return }

        for await event in realtimeSyncListener.successfulSyncEvents(accessTokenProvider: { [weak self] in
            guard let self else {
                throw SupabaseRESTError.requestFailed(401, "Your session expired. Please sign in again.")
            }

            return try await self.validAccessToken()
        }) {
            guard canAccessMonitoring else { return }

            let syncKey = event.deduplicationKey
            guard syncKey != lastRealtimeSyncKey else { continue }
            lastRealtimeSyncKey = syncKey

            try? await Task.sleep(for: .seconds(1))
            await refresh()
            print("Supabase realtime sync refresh completed: \(syncKey)")
        }
    }

    func nodes(for application: ApplicationSnapshot) -> [NodeSnapshot] {
        let now = Date.now
        return (nodeCache[application.id] ?? []).filter { $0.isReporting(asOf: now) }
    }

    func loadNodes(for application: ApplicationSnapshot) async -> [NodeSnapshot] {
        guard canAccessMonitoring else {
            return nodes(for: application)
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchNodes(
                    applicationID: application.id,
                    accessToken: accessToken
                )
            }
            let now = Date.now
            let nodes = dtos.map(SupabaseModelMapper.node(from:)).filter { $0.isReporting(asOf: now) }
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
        guard canAccessMonitoring else {
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
        accessStatus = .unknown
        signUpMessage = nil
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        incidentCache.removeAll()
        chartCache.removeAll()
        applications = []
        cachedApplications = []
        lastLoadedAt = nil
        dataState = .failed(message: message)
        errorMessage = message
        chartCacheRevision += 1
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
