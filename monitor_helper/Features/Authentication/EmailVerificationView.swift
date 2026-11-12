import SwiftUI

struct EmailVerificationView: View {
    @Bindable var store: MonitoringStore
    @State private var flow: EmailVerificationFlow
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmationFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: MonitoringStore, email: String, purpose: EmailVerificationPurpose, emailAlreadySent: Bool) {
        self.store = store
        _flow = State(initialValue: EmailVerificationFlow(email: email, purpose: purpose, emailAlreadySent: emailAlreadySent))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: flow.step == .success ? "checkmark.shield.fill" : "envelope")
                        .font(.system(size: 36)).foregroundStyle(AppTheme.accent)
                    Text(title).font(.title).fontWeight(.semibold)
                    Text(explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    switch flow.step {
                    case .request:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email address").font(.subheadline).fontWeight(.medium)
                            TextField("name@example.com", text: $flow.email)
                                .keyboardType(.emailAddress).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder).controlSize(.large)
                                .submitLabel(.send).onSubmit { Task { await flow.sendCode() } }
                        }
                        primaryButton("Send code") { await flow.sendCode() }
                    case .code:
                        Text(flow.email).font(.subheadline).fontWeight(.semibold).textSelection(.enabled)
                        TextField("8-digit code", text: $code)
                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder).controlSize(.large)
                            .accessibilityLabel("Email verification code")
                            .onChange(of: code) { _, value in code = String(value.filter { !$0.isWhitespace }.prefix(AuthenticationInput.emailCodeLength)) }
                        primaryButton(flow.purpose == .signup ? "Verify Email" : "Continue") {
                            if let session = await flow.verify(code: code) {
                                await store.completeEmailVerification(session)
                                if store.isAuthenticated { dismiss() }
                            }
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = flow.secondsUntilResend(at: context.date)
                            Button(remaining > 0 ? "Resend code in \(remaining)s" : "Resend code") {
                                code = ""
                                Task { await flow.sendCode() }
                            }.disabled(flow.isBusy || remaining > 0).frame(minHeight: 44)
                        }
                        Text("Check spam or junk. Codes expire after 15 minutes and can be used once. Use the most recent email, or request a new code if it expires.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .newPassword:
                        AuthenticationPasswordField(title: "New password", text: $password, isNewPassword: true, submitLabel: .next, focus: $passwordFocused) { confirmationFocused = true }
                        NewPasswordGuidance(password: password)
                        AuthenticationPasswordField(title: "Confirm new password", text: $confirmation, isNewPassword: true, focus: $confirmationFocused) {
                            Task { await flow.updatePassword(password, confirmation: confirmation) }
                        }
                        if !confirmation.isEmpty && password != confirmation {
                            Text("Passwords don't match yet.").font(.caption).foregroundStyle(.red)
                        }
                        primaryButton("Save New Password") { await flow.updatePassword(password, confirmation: confirmation) }
                    case .success:
                        Button("Back to Sign In") { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    }
                    if let error = flow.errorMessage { AuthenticationNotice(message: error) }
                    if let error = store.errorMessage { AuthenticationNotice(message: error) }
                }
                .frame(maxWidth: 500).padding(AppTheme.screenPadding).padding(.top, 24).frame(maxWidth: .infinity)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle(flow.purpose == .signup ? "Verify Email" : "Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow.step == .success ? "Done" : "Cancel") { dismiss() }.disabled(flow.isBusy)
                }
            }
            .interactiveDismissDisabled(flow.isBusy)
            .onChange(of: flow.step) { _, step in if step == .success { password = ""; confirmation = "" } }
            .onDisappear { flow.cancel(); code = ""; password = ""; confirmation = "" }
        }
    }

    private var title: String {
        switch flow.step {
        case .request: return flow.purpose == .signup ? "Verify your email" : "Forgot your password?"
        case .code: return "Check your email"
        case .newPassword: return "Choose a new password"
        case .success: return "Password updated"
        }
    }

    private var explanation: String {
        switch flow.step {
        case .request:
            return flow.purpose == .signup ? "Enter the email used to request access. We'll send a new verification code if confirmation is still needed." : "Enter your account email. If an account exists, we'll send a code to reset your password."
        case .code:
            return flow.purpose == .signup ? "If this address needs verification, a code is on its way. Enter it below. Once verified, an administrator will review your access request." : "If an account exists for this address, a reset code is on its way. Enter it below to continue."
        case .newPassword: return "Choose a unique password you haven't used elsewhere."
        case .success: return "You can now sign in with your new password. Your monitoring access approval stays the same."
        }
    }

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                if flow.isBusy { ProgressView().tint(.white) }
                Text(flow.isBusy ? "Please wait…" : title).fontWeight(.semibold)
            }.frame(maxWidth: .infinity, minHeight: 36)
        }.buttonStyle(.borderedProminent).disabled(flow.isBusy)
    }
}
