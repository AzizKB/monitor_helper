//
//  SupabaseRealtimeSyncListener.swift
//  monitor_helper
//

import Foundation

struct SupabaseSyncRunEvent: Equatable {
    let id: String?
    let completedAt: String?

    var deduplicationKey: String {
        completedAt ?? id ?? UUID().uuidString
    }
}

final class SupabaseRealtimeSyncListener {
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

    func successfulSyncEvents(
        accessTokenProvider: @escaping () async throws -> String
    ) -> AsyncStream<SupabaseSyncRunEvent> {
        AsyncStream { continuation in
            let listenerTask = Task {
                await listen(accessTokenProvider: accessTokenProvider, continuation: continuation)
            }

            continuation.onTermination = { _ in
                listenerTask.cancel()
            }
        }
    }

    private func listen(
        accessTokenProvider: @escaping () async throws -> String,
        continuation: AsyncStream<SupabaseSyncRunEvent>.Continuation
    ) async {
        var reconnectDelaySeconds: UInt64 = 3

        while !Task.isCancelled {
            do {
                let accessToken = try await accessTokenProvider()
                try await connectAndReceive(accessToken: accessToken, continuation: continuation)
                reconnectDelaySeconds = 3
            } catch {
                guard !Self.isCancellation(error) else { break }
                print("Supabase realtime listener disconnected: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(reconnectDelaySeconds))
                reconnectDelaySeconds = min(reconnectDelaySeconds * 2, 60)
            }
        }

        continuation.finish()
    }

    private func connectAndReceive(
        accessToken: String,
        continuation: AsyncStream<SupabaseSyncRunEvent>.Continuation
    ) async throws {
        let socket = session.webSocketTask(with: realtimeURL)
        socket.resume()

        let heartbeatTask = Task {
            await sendHeartbeat(to: socket)
        }

        defer {
            heartbeatTask.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }

        try await sendJoin(accessToken: accessToken, to: socket)
        print("Supabase realtime listener connected to sync_runs")

        while !Task.isCancelled {
            let message = try await socket.receive()

            guard case let .string(text) = message else {
                continue
            }

            if let event = syncRunEvent(from: text) {
                continuation.yield(event)
            }
        }
    }

    private var realtimeURL: URL {
        var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: publishableKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]
        return components.url!
    }

    private func sendJoin(accessToken: String, to socket: URLSessionWebSocketTask) async throws {
        let payload: [String: Any] = [
            "topic": "realtime:public:sync_runs",
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["self": false],
                    "presence": ["key": ""],
                    "postgres_changes": [
                        [
                            "event": "*",
                            "schema": "public",
                            "table": "sync_runs"
                        ]
                    ]
                ],
                "access_token": accessToken
            ],
            "ref": "1",
            "join_ref": "1"
        ]

        try await socket.send(.string(Self.jsonString(from: payload)))
    }

    private func sendHeartbeat(to socket: URLSessionWebSocketTask) async {
        var ref = 2

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { break }

            let heartbeat: [String: Any] = [
                "topic": "phoenix",
                "event": "heartbeat",
                "payload": [:],
                "ref": "\(ref)"
            ]
            ref += 1

            try? await socket.send(.string(Self.jsonString(from: heartbeat)))
        }
    }

    private func syncRunEvent(from text: String) -> SupabaseSyncRunEvent? {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["event"] as? String == "postgres_changes",
            let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }

        let changeData = payload["data"] as? [String: Any] ?? payload
        let record = changeData["record"] as? [String: Any]
            ?? changeData["new"] as? [String: Any]
            ?? changeData

        guard
            (record["status"] as? String)?.lowercased() == "success",
            record["completed_at"] != nil
        else {
            return nil
        }

        let errorCount = Self.intValue(record["error_count"]) ?? 0
        guard errorCount == 0 else { return nil }

        return SupabaseSyncRunEvent(
            id: record["id"] as? String,
            completedAt: record["completed_at"] as? String
        )
    }

    private static func jsonString(from object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? Double {
            return Int(value)
        }

        if let value = value as? String {
            return Int(value)
        }

        return nil
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
