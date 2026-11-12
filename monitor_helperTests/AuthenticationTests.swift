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
}

private final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var malformed = false

    nonisolated static func reset() { lock.lock(); defer { lock.unlock() }; captured = []; malformed = false }
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
        Self.lock.lock(); Self.captured.append(savedRequest); let malformed = Self.malformed; Self.lock.unlock()
        let path = request.url!.path
        let status = path.hasSuffix("logout") ? 204 : 200
        let body = path.hasSuffix("verify") ? (malformed ? #"{"access_token":"sensitive-token","expires_in":"invalid-integer"}"# : #"{"access_token":"test-token","refresh_token":"test-refresh","expires_in":3600,"user":{"id":"test-user","email":"u@example.com"}}"#) : "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        if status != 204 { client?.urlProtocol(self, didLoad: Data(body.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    nonisolated override func stopLoading() {}
}
