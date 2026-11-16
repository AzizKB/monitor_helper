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
        let channel = "realtime:public:sync_runs"
        return events(
            channel: channel,
            configuration: [
                "postgres_changes": [["event": "*", "schema": "public", "table": "sync_runs"]]
            ],
            accessTokenProvider: accessTokenProvider,
            decode: syncRunEvent(from:)
        )
    }

    func accessChanges(
        userID: UUID,
        accessTokenProvider: @escaping () async throws -> String
    ) -> AsyncStream<Void> {
        let channel = "realtime:mobile-access:\(userID.uuidString.lowercased())"
        return events(
            channel: channel,
            configuration: ["private": true],
            accessTokenProvider: accessTokenProvider
        ) { text in
            Self.isAccessChangeMessage(text, channel: channel) ? () : nil
        }
    }

    static func isAccessChangeMessage(_ text: String, channel: String) -> Bool {
        guard let message = messageObject(from: text),
              message["topic"] as? String == channel,
              message["event"] as? String == "broadcast",
              let payload = message["payload"] as? [String: Any]
        else { return false }
        return payload["event"] as? String == "access_changed"
    }

    private func events<Event: Sendable>(
        channel: String,
        configuration: [String: Any],
        accessTokenProvider: @escaping () async throws -> String,
        decode: @escaping (String) -> Event?
    ) -> AsyncStream<Event> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let listenerTask = Task {
                await listen(
                    channel: channel,
                    configuration: configuration,
                    accessTokenProvider: accessTokenProvider,
                    continuation: continuation,
                    decode: decode
                )
            }

            continuation.onTermination = { _ in
                listenerTask.cancel()
            }
        }
    }

    private func listen<Event: Sendable>(
        channel: String,
        configuration: [String: Any],
        accessTokenProvider: @escaping () async throws -> String,
        continuation: AsyncStream<Event>.Continuation,
        decode: (String) -> Event?
    ) async {
        var reconnectDelaySeconds: UInt64 = 3

        while !Task.isCancelled {
            do {
                let accessToken = try await accessTokenProvider()
                try await connectAndReceive(channel: channel, configuration: configuration, accessToken: accessToken) {
                    if let event = decode($0) { continuation.yield(event) }
                }
                reconnectDelaySeconds = 3
            } catch {
                guard !Self.isCancellation(error) else { break }
                try? await Task.sleep(for: .seconds(reconnectDelaySeconds))
                reconnectDelaySeconds = min(reconnectDelaySeconds * 2, 60)
            }
        }

        continuation.finish()
    }

    private func connectAndReceive(
        channel: String,
        configuration: [String: Any],
        accessToken: String,
        receive: (String) -> Void
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

        try await withTaskCancellationHandler {
            try await sendJoin(channel: channel, configuration: configuration, accessToken: accessToken, to: socket)

            while !Task.isCancelled {
                let message = try await socket.receive()
                if case let .string(text) = message {
                    if Self.channelClosed(text, channel: channel) {
                        throw URLError(.networkConnectionLost)
                    }
                    receive(text)
                }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
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

    private func sendJoin(
        channel: String, configuration: [String: Any], accessToken: String, to socket: URLSessionWebSocketTask
    ) async throws {
        let config = configuration.merging([
            "broadcast": ["self": false], "presence": ["key": ""], "postgres_changes": []
        ]) { supplied, _ in supplied }
        let payload: [String: Any] = [
            "topic": channel,
            "event": "phx_join",
            "payload": [
                "config": config,
                "access_token": accessToken
            ],
            "ref": "1",
            "join_ref": "1"
        ]

        try await socket.send(.string(Self.jsonString(from: payload)))
    }

    private static func messageObject(from text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    private static func channelClosed(_ text: String, channel: String) -> Bool {
        guard let message = messageObject(from: text), message["topic"] as? String == channel else { return false }
        switch message["event"] as? String {
        case "phx_error", "phx_close": return true
        case "phx_reply":
            return message["ref"] as? String == "1"
                && (message["payload"] as? [String: Any])?["status"] as? String == "error"
        default: return false
        }
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
            let object = Self.messageObject(from: text),
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
