import Foundation
import Observation

@MainActor
@Observable
final class EmailVerificationFlow {
    enum Step { case request, code, newPassword, success }
    let purpose: EmailVerificationPurpose
    var email: String
    private(set) var step: Step
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var nextSendAt = Date.distantPast
    private var recoverySession: StoredSupabaseSession?
    private let client: SupabaseRESTClient

    init(email: String, purpose: EmailVerificationPurpose, emailAlreadySent: Bool = false, client: SupabaseRESTClient? = nil) {
        self.email = AuthenticationInput.normalizedEmail(email)
        self.purpose = purpose
        self.step = emailAlreadySent ? .code : .request
        self.client = client ?? SupabaseRESTClient()
        if emailAlreadySent { nextSendAt = .now.addingTimeInterval(60) }
    }

    func secondsUntilResend(at date: Date = .now) -> Int {
        max(0, Int(ceil(nextSendAt.timeIntervalSince(date))))
    }

    func sendCode() async {
        guard !isBusy, secondsUntilResend() == 0 else { return }
        guard AuthenticationInput.isValidEmail(email) else {
            errorMessage = "Enter a valid email address, such as name@example.com."
            return
        }
        email = AuthenticationInput.normalizedEmail(email)
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if purpose == .signup { try await client.resendConfirmation(email: email) }
            else { try await client.requestPasswordReset(email: email) }
            step = .code
            nextSendAt = .now.addingTimeInterval(60)
        } catch {
            // A recovery request must not disclose whether the address has an account.
            if purpose == .recovery, case let SupabaseRESTError.requestFailed(_, body) = error,
               let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["error_code"] as? String == "user_not_found" {
                step = .code
                nextSendAt = .now.addingTimeInterval(60)
            } else { errorMessage = AuthenticationMessage.error(error, action: .recover) }
        }
    }

    func verify(code: String) async -> SupabaseAuthSession? {
        guard !isBusy, step == .code else { return nil }
        guard AuthenticationInput.isValidCode(code) else {
            errorMessage = "Enter the complete 8-digit code from your email."
            return nil
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let session = try await client.verifyEmailCode(email: email, code: code, purpose: purpose)
            if purpose == .recovery {
                // Recovery credentials stay in memory and never open monitoring or enter Keychain.
                recoverySession = StoredSupabaseSession(authSession: session)
                step = .newPassword
                return nil
            }
            return session
        } catch {
            errorMessage = AuthenticationMessage.error(error, action: .verify)
            return nil
        }
    }

    func updatePassword(_ password: String, confirmation: String) async {
        guard !isBusy, step == .newPassword else { return }
        guard AuthenticationInput.isValidNewPassword(password), password == confirmation else {
            errorMessage = "Use 12 or more characters with uppercase and lowercase letters, a number, and a symbol. Make sure both passwords match."
            return
        }
        guard let session = recoverySession, !session.isExpiringSoon(buffer: 0) else {
            recoverySession = nil
            step = .request
            errorMessage = "Your recovery session expired. Request a new code to continue."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.updatePassword(password, accessToken: session.accessToken)
            try? await client.revokeSessions(accessToken: session.accessToken)
            recoverySession = nil
            step = .success
        } catch { errorMessage = AuthenticationMessage.error(error, action: .updatePassword) }
    }

    func cancel() {
        recoverySession = nil
        errorMessage = nil
    }
}
