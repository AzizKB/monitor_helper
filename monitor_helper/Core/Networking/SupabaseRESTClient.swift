//
//  SupabaseRESTClient.swift
//  monitor_helper
//

import Foundation

enum SupabaseRESTError: LocalizedError {
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case let .requestFailed(statusCode, message):
            return "Supabase request failed (\(statusCode)): \(message)"
        }
    }
}

struct SupabaseRESTClient {
    private let projectURL: URL
    private let publishableKey: String
    private let session: URLSession

    init(
        projectURL: URL = SupabaseConfiguration.projectURL,
        publishableKey: String = SupabaseConfiguration.publishableKey,
        session: URLSession = .shared
    ) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.session = session
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

    func fetchMonitorApplications(accessToken: String) async throws -> [SupabaseMonitorApplicationDTO] {
        var components = URLComponents(url: url(path: "/rest/v1/v_monitor_applications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyReadHeaders(to: &request, accessToken: accessToken)

        return try await perform(request, as: [SupabaseMonitorApplicationDTO].self)
    }

    func fetchNodes(applicationID: UUID, accessToken: String) async throws -> [SupabaseApplicationNodeDTO] {
        var components = URLComponents(url: url(path: "/rest/v1/v_application_nodes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "application_id", value: "eq.\(applicationID.uuidString)"),
            URLQueryItem(name: "select", value: "*")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyReadHeaders(to: &request, accessToken: accessToken)

        return try await perform(request, as: [SupabaseApplicationNodeDTO].self)
    }

    func fetchMetricChart(
        applicationID: UUID,
        metricKey: String,
        minutes: Int,
        limit: Int,
        accessToken: String
    ) async throws -> [SupabaseChartPointDTO] {
        var request = URLRequest(url: url(path: "/rest/v1/rpc/get_application_metric_chart"))
        request.httpMethod = "POST"
        applyReadHeaders(to: &request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ApplicationMetricChartRequest(
                applicationID: applicationID.uuidString,
                metricKey: metricKey,
                minutes: minutes,
                limit: limit
            )
        )

        return try await perform(request, as: [SupabaseChartPointDTO].self)
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
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseRESTError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No response body"
            throw SupabaseRESTError.requestFailed(httpResponse.statusCode, message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

private struct ApplicationMetricChartRequest: Encodable {
    let applicationID: String
    let metricKey: String
    let minutes: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case applicationID = "p_application_id"
        case metricKey = "p_metric_key"
        case minutes = "p_minutes"
        case limit = "p_limit"
    }
}
