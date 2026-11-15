//
//  SupabaseRESTClient.swift
//  monitor_helper
//

import Foundation

enum SupabaseRESTError: LocalizedError {
    case invalidResponse
    case requestFailed(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case let .requestFailed(statusCode, _):
            return "The server could not complete the request (\(statusCode))."
        case let .decodingFailed(message):
            return "Supabase response could not be decoded: \(message)"
        }
    }
}

struct SupabaseRESTClient {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private let projectURL: URL
    private let publishableKey: String
    private let session: URLSession

    init(
        projectURL: URL = SupabaseConfiguration.projectURL,
        publishableKey: String = SupabaseConfiguration.publishableKey,
        session: URLSession? = nil
    ) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.session = session ?? Self.privateSession
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        var request = URLRequest(url: url(path: "/auth/v1/token"))
        request.url?.append(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        return try await perform(request, as: SupabaseAuthSession.self)
    }

    func signUp(email: String, password: String) async throws -> SupabaseSignUpResponse {
        var request = URLRequest(url: url(path: "/auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        return try await perform(request, as: SupabaseSignUpResponse.self)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        var request = URLRequest(url: url(path: "/auth/v1/token"))
        request.url?.append(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RefreshSessionRequest(refreshToken: refreshToken)
        )

        return try await perform(request, as: SupabaseAuthSession.self)
    }

    func requestPasswordReset(email: String) async throws {
        _ = try await responseData(authRequest(path: "recover", body: ["email": email]))
    }

    func resendConfirmation(email: String) async throws {
        _ = try await responseData(authRequest(path: "resend", body: ["email": email, "type": "signup"]))
    }

    func verifyEmailCode(email: String, code: String, purpose: EmailVerificationPurpose) async throws -> SupabaseAuthSession {
        try await perform(authRequest(path: "verify", body: ["email": email, "token": code, "type": purpose.rawValue]), as: SupabaseAuthSession.self)
    }

    func updatePassword(_ password: String, accessToken: String) async throws {
        _ = try await responseData(authRequest(path: "user", method: "PUT", body: ["password": password], accessToken: accessToken))
    }

    func revokeSessions(accessToken: String, scope: SignOutScope = .global) async throws {
        var request = try authRequest(path: "logout", body: [:], accessToken: accessToken)
        request.url?.append(queryItems: [URLQueryItem(name: "scope", value: scope.rawValue)])
        request.timeoutInterval = 10
        _ = try await responseData(request)
    }

    enum SignOutScope: String { case local, global }

    private func authRequest(path: String, method: String = "POST", body: [String: String], accessToken: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: url(path: "/auth/v1/\(path)"))
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func fetchMobileAccessStatus(accessToken: String) async throws -> [SupabaseMobileAccessDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_mobile_access_status"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        return try await perform(request, as: [SupabaseMobileAccessDTO].self)
    }

    func fetchMonitorApplications(minutes: Int, accessToken: String) async throws -> [SupabaseMonitorApplicationDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_monitor_applications_v2"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MonitorApplicationsRequest(windowMinutes: minutes)
        )

        return try await perform(request, as: [SupabaseMonitorApplicationDTO].self)
    }

    func fetchNodes(applicationID: UUID, accessToken: String) async throws -> [SupabaseApplicationNodeDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_application_nodes"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ApplicationNodesRequest(applicationID: applicationID.uuidString)
        )

        return try await perform(request, as: [SupabaseApplicationNodeDTO].self)
    }

    func fetchMetricChart(
        applicationID: UUID,
        metricKey: String,
        minutes: Int,
        endAt: Date,
        accessToken: String
    ) async throws -> [SupabaseChartPointDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_application_metric_chart_series"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ApplicationMetricChartRequest(
                applicationID: applicationID.uuidString,
                metricKey: metricKey,
                minutes: minutes,
                endAt: endAt.ISO8601Format()
            )
        )

        return try await perform(request, as: [SupabaseChartPointDTO].self)
    }

    func fetchIncidents(
        applicationID: UUID,
        limit: Int,
        accessToken: String
    ) async throws -> [SupabaseIncidentDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_application_incidents"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ApplicationIncidentsRequest(
                applicationID: applicationID.uuidString,
                limit: limit
            )
        )

        return try await perform(request, as: [SupabaseIncidentDTO].self)
    }

    private func applyReadHeaders(to request: inout URLRequest, accessToken: String) {
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    private func url(path: String) -> URL {
        var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url!
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await responseData(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Auth responses can contain tokens. Never include response bodies in errors.
            throw SupabaseRESTError.decodingFailed("The response format was not recognized.")
        }
    }

    private func responseData(_ request: URLRequest) async throws -> Data {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseRESTError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No response body"
            throw SupabaseRESTError.requestFailed(httpResponse.statusCode, message)
        }

        return data
    }
}

private struct MonitorApplicationsRequest: Encodable {
    let windowMinutes: Int

    enum CodingKeys: String, CodingKey {
        case windowMinutes = "p_window_minutes"
    }
}

private struct RefreshSessionRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct ApplicationMetricChartRequest: Encodable {
    let applicationID: String
    let metricKey: String
    let minutes: Int
    let endAt: String

    enum CodingKeys: String, CodingKey {
        case applicationID = "p_application_id"
        case metricKey = "p_metric_key"
        case minutes = "p_window_minutes"
        case endAt = "p_end_at"
    }
}

private struct ApplicationNodesRequest: Encodable {
    let applicationID: String

    enum CodingKeys: String, CodingKey {
        case applicationID = "p_application_id"
    }
}

private struct ApplicationIncidentsRequest: Encodable {
    let applicationID: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case applicationID = "p_application_id"
        case limit = "p_limit"
    }
}
