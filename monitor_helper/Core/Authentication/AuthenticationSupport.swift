import Foundation

enum AuthenticationInput {
    static let minimumPasswordLength = 12
    static let maximumPasswordBytes = 72
    static let emailCodeLength = 8
    static let passwordSymbols = #"!@#$%^&*()_+-=[]{};'\:"|<>?,./`~"#

    static func hasBothLetterCases(_ password: String) -> Bool {
        password.range(of: "[a-z]", options: .regularExpression) != nil && password.range(of: "[A-Z]", options: .regularExpression) != nil
    }

    static func hasNumberAndSymbol(_ password: String) -> Bool {
        password.range(of: "[0-9]", options: .regularExpression) != nil && password.contains { passwordSymbols.contains($0) }
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidEmail(_ email: String) -> Bool {
        let value = normalizedEmail(email)
        return value.count <= 254 && value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    static func isValidNewPassword(_ password: String) -> Bool {
        password.count >= minimumPasswordLength && password.utf8.count <= maximumPasswordBytes
            && hasBothLetterCases(password) && hasNumberAndSymbol(password)
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == emailCodeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

enum AuthenticationAction { case signIn, signUp, verify, recover, updatePassword, checkAccess }

enum AuthenticationMessage {
    static func error(_ error: Error, action: AuthenticationAction) -> String {
        if let networkError = error as? URLError {
            switch networkError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The connection took too long. Please try again."
            default:
                return "We couldn't connect. Please try again shortly."
            }
        }
        guard case let SupabaseRESTError.requestFailed(status, body) = error else {
            return "We couldn't complete that request. Please try again."
        }
        let object = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let code = object?["error_code"] as? String ?? object?["code"] as? String ?? ""
        switch code {
        case "email_not_confirmed":
            return "Please verify your email before signing in. You can request a new verification code below."
        case "email_address_invalid", "validation_failed":
            return "Check your email address and try again."
        case "weak_password":
            return "Use at least 12 characters with uppercase and lowercase letters, a number, and a symbol. Avoid common or previously exposed passwords."
        case "same_password":
            return "Choose a password different from your current password."
        case "otp_expired", "otp_disabled":
            return "That code is invalid or has expired. Check the latest email or request a new code."
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_password_reset_rate_limit":
            return "Too many attempts. Please wait a minute before trying again."
        case "user_already_exists", "email_exists":
            return "If you've already requested access, sign in or reset your password. Otherwise, check your email for verification."
        default:
            if status == 429 { return "Too many attempts. Please wait a minute before trying again." }
            if status >= 500 { return "The service is temporarily unavailable. Please try again shortly." }
            switch action {
            case .signIn:
                return "The email or password is incorrect. Check both, or use Forgot password."
            case .verify:
                return "We couldn't verify that code. Use the code from your latest email or request a new one."
            case .signUp:
                return "We couldn't create your account. Check your details and try again. If you already have an account, sign in."
            case .recover:
                return "We couldn't send the email right now. Please wait a minute and try again."
            case .updatePassword:
                return "We couldn't update your password. Your recovery session may have expired; request a new code and try again."
            case .checkAccess:
                return "We couldn't check your access approval. Please try again."
            }
        }
    }
}

enum EmailVerificationPurpose: String, Identifiable {
    case signup, recovery
    var id: String { rawValue }
}
