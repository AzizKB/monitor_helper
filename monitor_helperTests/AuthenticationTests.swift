import Foundation
import Testing
@testable import monitor_helper

@MainActor
struct AuthenticationTests {
    @Test func emailValidationTrimsWhitespaceAndRejectsMalformedAddresses() {
        #expect(AuthenticationInput.isValidEmail("  user@example.com\n"))
        for email in ["", "user", "user@", "a@b", "a b@example.com", "a@@example.com"] {
            #expect(!AuthenticationInput.isValidEmail(email))
        }
    }

    @Test func newPasswordsAllowPassphrasesButRespectTheBackendByteLimit() {
        #expect(AuthenticationInput.isValidNewPassword("A long unique phrase 42!"))
        #expect(!AuthenticationInput.isValidNewPassword("too short"))
        #expect(AuthenticationInput.isValidNewPassword("Aa1!" + String(repeating: "a", count: 68)))
        #expect(!AuthenticationInput.isValidNewPassword("Aa1!" + String(repeating: "a", count: 69)))
        #expect(!AuthenticationInput.isValidNewPassword(String(repeating: "🔒", count: 19)))
    }

    @Test func verificationCodesAcceptOnlyCompleteASCIIDigits() {
        #expect(!AuthenticationInput.isValidCode("123456"))
        #expect(AuthenticationInput.isValidCode("12345678"))
        for code in ["123", "12345x", "١٢٣٤٥٦", "12345678901"] { #expect(!AuthenticationInput.isValidCode(code)) }
    }

    @Test func incorrectCredentialsDoNotRevealAccountExistenceOrRawServerDetails() {
        let error = SupabaseRESTError.requestFailed(400, #"{"error_code":"invalid_credentials","msg":"private diagnostic"}"#)
        let message = AuthenticationMessage.error(error, action: .signIn)
        #expect(message.contains("email or password is incorrect"))
        #expect(!message.contains("private diagnostic"))
        #expect(!message.contains("Supabase"))
    }

    @Test func commonFailuresGiveActionableMessages() {
        let cases = [("email_not_confirmed", "verify your email"), ("otp_expired", "expired"), ("same_password", "different"), ("weak_password", "12 characters"), ("over_email_send_rate_limit", "wait a minute")]
        for (code, expected) in cases {
            let error = SupabaseRESTError.requestFailed(400, "{\"error_code\":\"\(code)\"}")
            #expect(AuthenticationMessage.error(error, action: .verify).contains(expected))
        }
        #expect(AuthenticationMessage.error(URLError(.notConnectedToInternet), action: .signIn).contains("offline"))
        #expect(AuthenticationMessage.error(SupabaseRESTError.requestFailed(503, "secret"), action: .recover).contains("temporarily"))
    }

    @Test func signupDecodesConfirmedAndUnconfirmedResponseShapes() throws {
        let pending = try JSONDecoder().decode(SupabaseSignUpResponse.self, from: Data(#"{"id":"pending","email":"u@example.com"}"#.utf8))
        #expect(pending.session == nil)
        let confirmed = try JSONDecoder().decode(SupabaseSignUpResponse.self, from: Data(#"{"access_token":"test-token","refresh_token":"test-refresh","expires_in":3600,"user":{"id":"confirmed","email":"u@example.com"}}"#.utf8))
        #expect(confirmed.session?.user?.id == "confirmed")
    }
}

@Suite(.serialized)
@MainActor
struct EmailVerificationFlowTests {
    private func client() -> SupabaseRESTClient {
        AuthURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthURLProtocol.self]
        return SupabaseRESTClient(projectURL: URL(string: "https://auth.example.test")!, publishableKey: "test-publishable", session: URLSession(configuration: config))
    }

    @Test func recoveryRequiresCodeBeforePasswordUpdateAndKeepsSessionSeparate() async throws {
        let flow = EmailVerificationFlow(email: " user@example.com ", purpose: .recovery, client: client())
        await flow.updatePassword("A long unique phrase 42!", confirmation: "A long unique phrase 42!")
        #expect(AuthURLProtocol.requests().isEmpty)
        await flow.sendCode()
        #expect(flow.step == .code)
        let result = await flow.verify(code: "12345678")
        #expect(result == nil)
        #expect(flow.step == .newPassword)
        await flow.updatePassword("A long unique phrase 42!", confirmation: "A long unique phrase 42!")
        #expect(flow.step == .success)
        let requests = AuthURLProtocol.requests()
        #expect(requests.map { $0.url!.path } == ["/auth/v1/recover", "/auth/v1/verify", "/auth/v1/user", "/auth/v1/logout"])
        #expect(requests[2].httpMethod == "PUT")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let verifyBody = try #require(requests[1].httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: verifyBody) as? [String: String])
        #expect(object["type"] == "recovery")
        #expect(object["email"] == "user@example.com")
    }

    @Test func cancelDiscardsRecoveryAuthority() async {
        let flow = EmailVerificationFlow(email: "u@example.com", purpose: .recovery, emailAlreadySent: true, client: client())
        _ = await flow.verify(code: "12345678")
        flow.cancel()
        await flow.updatePassword("A long unique phrase 42!", confirmation: "A long unique phrase 42!")
        #expect(flow.step == .request)
        #expect(AuthURLProtocol.requests().count == 1)
    }

    @Test func invalidInputsAndResendCooldownDoNotSendExtraRequests() async {
        let flow = EmailVerificationFlow(email: "bad", purpose: .recovery, client: client())
        await flow.sendCode()
        #expect(AuthURLProtocol.requests().isEmpty)
        flow.email = "u@example.com"
        await flow.sendCode()
        await flow.sendCode()
        _ = await flow.verify(code: "wrong")
        #expect(AuthURLProtocol.requests().count == 1)
        #expect(flow.secondsUntilResend() > 0)
    }

    @Test func signupVerificationReturnsSessionWithoutPasswordResetAuthority() async {
        let flow = EmailVerificationFlow(email: "u@example.com", purpose: .signup, emailAlreadySent: true, client: client())
        let result = await flow.verify(code: "12345678")
        #expect(result?.user?.email == "u@example.com")
        await flow.updatePassword("A long unique phrase 42!", confirmation: "A long unique phrase 42!")
        #expect(AuthURLProtocol.requests().count == 1)
    }

    @Test func malformedAuthResponseNeverLeaksTokensIntoErrorMessages() async {
        let client = client()
        AuthURLProtocol.useMalformedResponse()
        do {
            _ = try await client.verifyEmailCode(email: "u@example.com", code: "12345678", purpose: .recovery)
            Issue.record("Expected a decoding failure")
        } catch {
            #expect(!error.localizedDescription.contains("sensitive-token"))
        }
    }

    @Test func httpFailureDescriptionDoesNotExposeBackendBody() {
        let error = SupabaseRESTError.requestFailed(500, "private-backend-data")
        #expect(!error.localizedDescription.contains("private-backend-data"))
    }

    @Test func signOutDuringTokenRefreshCannotRestoreTheSession() async throws {
        let client = client()
        let storage = TestSessionStorage(session: Self.expiringSession)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        AuthURLProtocol.setResponse {
            if $0.url?.path == "/auth/v1/token" {
                signal.yield(())
                _ = release.wait(timeout: .now() + 5)
                return (200, Self.rotatedSession)
            }
            return (204, "")
        }
        let store = MonitoringStore(client: client, sessionStore: storage)
        let bootstrap = Task { await store.bootstrap(); signal.finish() }
        var iterator = started.makeAsyncIterator()
        try #require(await iterator.next() != nil)
        let revocation = store.signOut()
        release.signal()
        signal.finish()
        await bootstrap.value
        await revocation?.value

        #expect(!store.isAuthenticated)
        #expect(store.applications.isEmpty)
        #expect(storage.session == nil)
        #expect(storage.saveCount == 0)
        let logout = try #require(AuthURLProtocol.requests().first { $0.url?.path == "/auth/v1/logout" })
        #expect(URLComponents(url: logout.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "scope", value: "local")) == true)
    }

    @Test func concurrentAccessChecksShareOneTokenRotation() async throws {
        let client = client()
        let storage = TestSessionStorage(session: Self.expiringSession)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        AuthURLProtocol.setResponse {
            if $0.url?.path == "/auth/v1/token" {
                signal.yield(())
                _ = release.wait(timeout: .now() + 5)
                return (200, Self.rotatedSession)
            }
            return (200, #"[{"status":"approved"}]"#)
        }
        let store = MonitoringStore(client: client, sessionStore: storage)
        let bootstrap = Task { await store.bootstrap(); signal.finish() }
        var iterator = started.makeAsyncIterator()
        try #require(await iterator.next() != nil)
        let check = Task { await store.refreshMobileAccessStatus() }
        while !store.isCheckingAccess { await Task.yield() }
        release.signal()
        signal.finish()
        await bootstrap.value
        await check.value

        #expect(store.canAccessMonitoring)
        #expect(storage.saveCount == 1)
        #expect(AuthURLProtocol.requests().filter { $0.url?.path == "/auth/v1/token" }.count == 1)
    }

    @Test func accessSignalClearsOpenMonitoringBeforeBlockCheckReturns() async throws {
        let client = client()
        let storage = TestSessionStorage(session: Self.activeSession)
        AuthURLProtocol.setResponse {
            if $0.url?.path.hasSuffix("get_mobile_access_status") == true {
                return (200, #"[{"status":"approved"}]"#)
            }
            return (200, Self.applicationFixture)
        }
        let store = MonitoringStore(client: client, sessionStore: storage)
        await store.bootstrap()
        await store.refresh()
        try #require(store.applications.count == 1)

        let (calls, callSignal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        AuthURLProtocol.setResponse { _ in
            callSignal.yield(())
            _ = release.wait(timeout: .now() + 5)
            return (200, #"[{"status":"blocked"}]"#)
        }
        let (changes, changeSignal) = AsyncStream<Void>.makeStream()
        let listener = Task { await store.observeMobileAccessChanges(changes); callSignal.finish() }
        changeSignal.yield(())
        changeSignal.finish()
        var iterator = calls.makeAsyncIterator()
        try #require(await iterator.next() != nil)

        #expect(!store.canAccessMonitoring)
        #expect(store.applications.isEmpty)
        release.signal()
        await listener.value
        #expect(store.accessStatus.decision == .blocked)
        #expect(store.isAuthenticated)
    }

    @Test func missedSignalIsCaughtByForegroundPolling() async throws {
        let client = client()
        let storage = TestSessionStorage(session: Self.activeSession)
        AuthURLProtocol.setResponse { _ in (200, #"[{"status":"approved"}]"#) }
        let store = MonitoringStore(client: client, sessionStore: storage)
        await store.bootstrap()
        try #require(store.canAccessMonitoring)
        AuthURLProtocol.setResponse { _ in (200, #"[{"status":"blocked"}]"#) }
        let poll = Task { await store.pollMobileAccessWhileActive(interval: .milliseconds(15)) }
        for _ in 0..<80 {
            if store.accessStatus.decision == .blocked { break }
            try await Task.sleep(for: .milliseconds(15))
        }
        poll.cancel()
        await poll.value
        #expect(store.accessStatus.decision == .blocked)
        #expect(!store.canAccessMonitoring)
    }

    @Test func realtimeAccessSignalRequiresCorrectTopicAndEvent() {
        #expect(SupabaseRealtimeSyncListener.isAccessChangeMessage(
            #"{"topic":"realtime:mobile-access:own","event":"broadcast","payload":{"event":"access_changed","payload":{}}}"#,
            channel: "realtime:mobile-access:own"
        ))
        #expect(!SupabaseRealtimeSyncListener.isAccessChangeMessage(
            #"{"topic":"realtime:mobile-access:other","event":"broadcast","payload":{"event":"access_changed"}}"#,
            channel: "realtime:mobile-access:own"
        ))
        #expect(!SupabaseRealtimeSyncListener.isAccessChangeMessage(
            #"{"topic":"realtime:mobile-access:own","event":"phx_reply","payload":{"event":"access_changed"}}"#,
            channel: "realtime:mobile-access:own"
        ))
    }

    private static var activeSession: StoredSupabaseSession {
        StoredSupabaseSession(accessToken: "active-token", refreshToken: nil,
                              expiresAt: .distantFuture, userID: nil, userEmail: nil)
    }

    nonisolated private static var applicationFixture: String {
        #"[{"application_id":"00000000-0000-0000-0000-000000000001","application_name":"Monitoring test","display_name":"Monitoring test"}]"#
    }

    private static var expiringSession: StoredSupabaseSession {
        StoredSupabaseSession(accessToken: "before-rotation", refreshToken: "test-refresh",
                              expiresAt: .distantPast, userID: nil, userEmail: nil)
    }

    nonisolated private static var rotatedSession: String {
        #"{"access_token":"after-rotation","refresh_token":"rotated-test-refresh","expires_in":3600}"#
    }
}

@MainActor
private final class TestSessionStorage: MonitoringSessionStorage {
    var session: StoredSupabaseSession?
    private(set) var saveCount = 0

    init(session: StoredSupabaseSession?) { self.session = session }
    func load() throws -> StoredSupabaseSession? { session }
    func save(_ session: StoredSupabaseSession) throws {
        saveCount += 1
        self.session = session
    }
    func clear() throws { session = nil }
}

private final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var malformed = false
    nonisolated(unsafe) private static var response: (@Sendable (URLRequest) -> (Int, String))?

    nonisolated static func reset() { lock.lock(); defer { lock.unlock() }; captured = []; malformed = false; response = nil }
    nonisolated static func setResponse(_ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
        lock.lock(); defer { lock.unlock() }; response = handler
    }
    nonisolated static func useMalformedResponse() { lock.lock(); defer { lock.unlock() }; malformed = true }
    nonisolated static func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func startLoading() {
        var savedRequest = request
        if savedRequest.httpBody == nil, let stream = savedRequest.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let length = stream.read(&buffer, maxLength: buffer.count)
                if length <= 0 { break }; data.append(contentsOf: buffer.prefix(length))
            }
            savedRequest.httpBody = data
        }
        Self.lock.lock(); Self.captured.append(savedRequest); let malformed = Self.malformed; let custom = Self.response; Self.lock.unlock()
        let path = request.url!.path
        let (status, body) = custom?(savedRequest) ?? (
            path.hasSuffix("logout") ? 204 : 200,
            path.hasSuffix("verify") ? (malformed ? #"{"access_token":"sensitive-token","expires_in":"invalid-integer"}"# : #"{"access_token":"test-token","refresh_token":"test-refresh","expires_in":3600,"user":{"id":"test-user","email":"u@example.com"}}"#) : "{}"
        )
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        if status != 204 { client?.urlProtocol(self, didLoad: Data(body.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    nonisolated override func stopLoading() {}
}
