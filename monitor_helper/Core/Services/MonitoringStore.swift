//
//  MonitoringStore.swift
//  monitor_helper
//

import Foundation
import Observation

@MainActor
@Observable
final class MonitoringStore {
    private let supabaseClient: SupabaseRESTClient
    private let realtimeSyncListener = SupabaseRealtimeSyncListener()
    private let sessionStore: any MonitoringSessionStorage
    private var sessionEpoch = UUID()
    private var refreshTask: Task<Void, Error>?
    private var accessCheckID: UUID?
    private var lastAccessCheckAt: Date?
    private var refreshQueued = false
    private var summaryRefreshID: UUID?
    private var summaryRangeInFlight: MonitoringTimeRange?
    private var chartAnchor: Date?
    private var nodeCacheFetchedAt: [UUID: Date] = [:]

    init(client: SupabaseRESTClient? = nil, sessionStore: (any MonitoringSessionStorage)? = nil) {
        self.supabaseClient = client ?? SupabaseRESTClient()
        self.sessionStore = sessionStore ?? SupabaseSessionStore()
    }
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

        let epoch = sessionEpoch
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
            guard epoch == sessionEpoch else { return }
            if session != nil {
                errorMessage = AuthenticationMessage.error(error, action: .checkAccess)
            } else {
                expireSession(message: "Your saved session could not be restored. Please sign in again.")
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        signUpMessage = nil
        defer { isSigningIn = false }

        let epoch = sessionEpoch
        do {
            let authSession = try await supabaseClient.signIn(email: email, password: password)
            guard epoch == sessionEpoch, !Task.isCancelled else { return }
            let storedSession = StoredSupabaseSession(authSession: authSession)
            try sessionStore.save(storedSession)
            session = storedSession
            await refreshMobileAccessStatus()
        } catch {
            guard epoch == sessionEpoch, !Self.isCancellation(error) else { return }
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

        let epoch = sessionEpoch
        do {
            let response = try await supabaseClient.signUp(email: email, password: password)
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }

            if let authSession = response.session {
                let storedSession = StoredSupabaseSession(authSession: authSession)
                try sessionStore.save(storedSession)
                session = storedSession
                await refreshMobileAccessStatus()
            }

            signUpMessage = "Account created. Confirm your email, then wait for admin approval."
            return true
        } catch {
            guard epoch == sessionEpoch, !Self.isCancellation(error) else { return false }
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

        let epoch = sessionEpoch
        let checkID = UUID()
        accessCheckID = checkID
        isCheckingAccess = true
        defer {
            if accessCheckID == checkID {
                accessCheckID = nil
                isCheckingAccess = false
            }
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchMobileAccessStatus(accessToken: accessToken)
            }

            guard epoch == sessionEpoch, accessCheckID == checkID, !Task.isCancelled else { return }
            lastAccessCheckAt = .now
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
            } else {
                clearMonitoringData()
            }
        } catch {
            guard epoch == sessionEpoch, accessCheckID == checkID, !Self.isCancellation(error) else { return }
            lastAccessCheckAt = nil
            clearMonitoringData()
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

    @discardableResult
    func signOut() -> Task<Void, Never>? {
        let token = session?.accessToken
        resetSession()
        errorMessage = nil
        guard let token else { return nil }
        // Clear the device immediately, even if network revocation cannot complete.
        return Task { [supabaseClient] in
            try? await supabaseClient.revokeSessions(accessToken: token, scope: .local)
        }
    }

    private func resetSession() {
        sessionEpoch = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        accessCheckID = nil
        isCheckingAccess = false
        lastAccessCheckAt = nil
        summaryRefreshID = nil
        summaryRangeInFlight = nil
        isRefreshing = false
        refreshQueued = false
        try? sessionStore.clear()
        session = nil
        accessStatus = .unknown
        signUpMessage = nil
        clearMonitoringData()
    }

    private func clearMonitoringData() {
        isUsingLiveData = false
        hasLoadedLiveData = false
        lastRealtimeSyncKey = nil
        chartAnchor = nil
        applicationCacheByRange.removeAll()
        nodeCache.removeAll()
        nodeCacheFetchedAt.removeAll()
        incidentCache.removeAll()
        chartCache.removeAll()
        applications = []
        cachedApplications = []
        lastLoadedAt = nil
        dataState = .initial
        chartCacheRevision += 1
    }

    func refresh() async {
        guard canAccessMonitoring else { return }
        if isRefreshing {
            if summaryRangeInFlight != selectedTimeRange { refreshQueued = true }
            return
        }
        let refreshID = UUID()
        summaryRefreshID = refreshID
        isRefreshing = true
        defer {
            if summaryRefreshID == refreshID {
                isRefreshing = false
                summaryRangeInFlight = nil
                summaryRefreshID = nil
            }
        }
        repeat {
            refreshQueued = false
            await refreshSnapshot(for: selectedTimeRange)
        } while summaryRefreshID == refreshID && refreshQueued && canAccessMonitoring && !Task.isCancelled
    }

    private func refreshSnapshot(for range: MonitoringTimeRange) async {
        let epoch = sessionEpoch
        summaryRangeInFlight = range
        errorMessage = nil
        if !hasLoadedLiveData {
            dataState = .loading
        }

        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchMonitorApplications(
                    minutes: range.minutes,
                    accessToken: accessToken
                )
            }
            guard epoch == sessionEpoch, canAccessMonitoring, !Task.isCancelled else { return }
            guard selectedTimeRange == range else {
                refreshQueued = true
                return
            }
            let snapshots = dtos.map(SupabaseModelMapper.application(from:))
            let previousSync = applications.compactMap(\.lastSuccessfulSyncAt).max()
            let currentSync = snapshots.compactMap(\.lastSuccessfulSyncAt).max()
            let changedInventory = Set(applications.map(\.id)) != Set(snapshots.map(\.id))
            let windowNeedsUpdate = chartAnchor.map { Date.now.timeIntervalSince($0) >= 300 } ?? true
            let invalidateCharts = windowNeedsUpdate || previousSync != currentSync || changedInventory
            applications = snapshots
            cachedApplications = snapshots
            applicationCacheByRange[range] = snapshots
            isUsingLiveData = true
            hasLoadedLiveData = true
            lastLoadedAt = Date.now
            dataState = snapshots.isEmpty ? .empty : .live
            if invalidateCharts {
                chartAnchor = lastLoadedAt
                chartCache.removeAll()
                chartCacheRevision += 1
            }
        } catch {
            guard epoch == sessionEpoch, canAccessMonitoring, !Self.isCancellation(error) else { return }
            guard selectedTimeRange == range else {
                refreshQueued = true
                return
            }
            isUsingLiveData = hasLoadedLiveData
            applications = cachedApplications
            errorMessage = error.localizedDescription
            dataState = hasLoadedLiveData
                ? .cached(lastUpdated: lastLoadedAt ?? .now)
                : .failed(message: error.localizedDescription)
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

        if case .empty = chartCache[key] {
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
        let requestedEnd = chartAnchor ?? .now

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
            guard !Task.isCancelled else { return }
            await recheckAccessIfNeeded()
            await refresh()
        }
    }

    func recheckAccessIfNeeded(maxAge: TimeInterval = 60) async {
        guard !isCheckingAccess, session != nil else { return }
        if let lastAccessCheckAt, Date.now.timeIntervalSince(lastAccessCheckAt) < maxAge { return }
        await refreshMobileAccessStatus()
    }

    func nodes(for application: ApplicationSnapshot) -> [NodeSnapshot] {
        guard canAccessMonitoring else { return [] }
        let now = Date.now
        return (nodeCache[application.id] ?? []).filter { $0.isReporting(asOf: now) }
    }

    func loadNodes(for application: ApplicationSnapshot) async -> [NodeSnapshot] {
        guard canAccessMonitoring else { return [] }
        if let fetchedAt = nodeCacheFetchedAt[application.id], Date.now.timeIntervalSince(fetchedAt) < 30 {
            return nodes(for: application)
        }
        let epoch = sessionEpoch
        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchNodes(
                    applicationID: application.id,
                    accessToken: accessToken
                )
            }
            guard epoch == sessionEpoch, canAccessMonitoring, !Task.isCancelled else { return [] }
            let now = Date.now
            let nodes = dtos.map(SupabaseModelMapper.node(from:)).filter { $0.isReporting(asOf: now) }
            nodeCache[application.id] = nodes
            nodeCacheFetchedAt[application.id] = now
            return nodes
        } catch {
            guard epoch == sessionEpoch, canAccessMonitoring else { return [] }
            guard !Self.isCancellation(error) else {
                return nodes(for: application)
            }

            errorMessage = error.localizedDescription
            return nodes(for: application)
        }
    }

    func incidents(for application: ApplicationSnapshot) -> [IncidentSnapshot] {
        canAccessMonitoring ? incidentCache[application.id] ?? [] : []
    }

    func loadIncidents(for application: ApplicationSnapshot) async -> [IncidentSnapshot] {
        guard canAccessMonitoring else { return [] }
        let epoch = sessionEpoch
        do {
            let dtos = try await authenticatedRequest { accessToken in
                try await supabaseClient.fetchIncidents(
                    applicationID: application.id,
                    limit: 50,
                    accessToken: accessToken
                )
            }
            guard epoch == sessionEpoch, canAccessMonitoring, !Task.isCancelled else { return [] }
            let incidents = dtos.map(SupabaseModelMapper.incident(from:))
            incidentCache[application.id] = incidents
            return incidents
        } catch {
            guard epoch == sessionEpoch, canAccessMonitoring else { return [] }
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
        let epoch = sessionEpoch
        let accessToken = try await validAccessToken()
        try requireCurrentSession(epoch)

        do {
            let result = try await operation(accessToken)
            try requireCurrentSession(epoch)
            return result
        } catch SupabaseRESTError.requestFailed(401, _) {
            try requireCurrentSession(epoch)
            if session?.accessToken == accessToken {
                try await refreshStoredSession()
            }

            try requireCurrentSession(epoch)
            guard let refreshedAccessToken = session?.accessToken else { throw CancellationError() }
            do {
                let result = try await operation(refreshedAccessToken)
                try requireCurrentSession(epoch)
                return result
            } catch SupabaseRESTError.requestFailed(401, _) {
                try requireCurrentSession(epoch)
                if session?.accessToken == refreshedAccessToken {
                    expireSession(message: "Your session expired. Please sign in again.")
                }
                throw CancellationError()
            }
        }
    }

    private func requireCurrentSession(_ epoch: UUID) throws {
        guard sessionEpoch == epoch, session != nil else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func validAccessToken() async throws -> String {
        let epoch = sessionEpoch
        guard let currentSession = session else { throw CancellationError() }
        if currentSession.isExpiringSoon() {
            try await refreshStoredSession()
        }
        try requireCurrentSession(epoch)
        guard let accessToken = session?.accessToken else { throw CancellationError() }
        return accessToken
    }

    private func refreshStoredSession() async throws {
        let epoch = sessionEpoch
        if let refreshTask {
            try await refreshTask.value
            try requireCurrentSession(epoch)
            return
        }
        guard let currentSession = session, let refreshToken = currentSession.refreshToken, !refreshToken.isEmpty else {
            expireSession(message: "Your session expired. Please sign in again.")
            throw CancellationError()
        }

        let task = Task {
            do {
                let refreshedAuthSession = try await supabaseClient.refreshSession(refreshToken: refreshToken)
                try requireCurrentSession(epoch)
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
            } catch let error as SupabaseRESTError {
                if case let .requestFailed(status, _) = error,
                   [400, 401, 403].contains(status), sessionEpoch == epoch {
                    expireSession(message: "Your session expired. Please sign in again.")
                }
                throw error
            }
        }
        refreshTask = task
        defer { if sessionEpoch == epoch { refreshTask = nil } }
        try await task.value
        try requireCurrentSession(epoch)
    }

    private func expireSession(message: String) {
        resetSession()
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
