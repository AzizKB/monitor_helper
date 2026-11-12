import SwiftUI

struct AuthenticationView: View {
    @Bindable var store: MonitoringStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isRequestingAccess = false
    @State private var submitted = false
    @State private var emailWasEdited = false
    @State private var activeVerification: VerificationRequest?
    @AppStorage("authentication.rememberEmail") private var rememberEmail = true
    @AppStorage("authentication.savedEmail") private var savedEmail = ""
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmationFocused: Bool

    private var normalizedEmail: String { AuthenticationInput.normalizedEmail(email) }
    private var busy: Bool { store.isSigningIn || store.isSigningUp }

    private struct VerificationRequest: Identifiable {
        let id = UUID()
        let email: String
        let purpose: EmailVerificationPurpose
        var emailAlreadySent = false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "eye").font(.system(size: 32)).foregroundStyle(AppTheme.accent)
                        Text("Monitor Helper").font(.largeTitle).fontWeight(.semibold)
                        Text(isRequestingAccess ? "Create your account, verify your email, and request access to monitoring." : "Welcome back. Sign in to your monitoring workspace.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Authentication mode", selection: $isRequestingAccess) {
                        Text("Sign In").tag(false)
                        Text("Request Access").tag(true)
                    }
                    .pickerStyle(.segmented).disabled(busy)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email address").font(.subheadline).fontWeight(.medium)
                            TextField("name@example.com", text: $email)
                                .textContentType(.username).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder).controlSize(.large)
                                .focused($emailFocused).submitLabel(.next)
                                .onSubmit { emailFocused = false; passwordFocused = true }
                            if (submitted || emailWasEdited) && !AuthenticationInput.isValidEmail(email) {
                                Text("Enter a valid email address, such as name@example.com.").font(.caption).foregroundStyle(.red)
                            }
                        }
                        AuthenticationPasswordField(title: "Password", text: $password, isNewPassword: isRequestingAccess, submitLabel: isRequestingAccess ? .next : .go, focus: $passwordFocused) {
                            if isRequestingAccess { confirmationFocused = true } else { submit() }
                        }
                        if isRequestingAccess {
                            NewPasswordGuidance(password: password)
                            AuthenticationPasswordField(title: "Confirm password", text: $confirmPassword, isNewPassword: true, focus: $confirmationFocused, onSubmit: submit)
                            if (!confirmPassword.isEmpty || submitted) && password != confirmPassword {
                                Text("Passwords don't match yet.").font(.caption).foregroundStyle(.red)
                            }
                        } else {
                            Button("Forgot password?") {
                                store.clearAuthenticationMessages()
                                activeVerification = VerificationRequest(email: normalizedEmail, purpose: .recovery)
                            }.font(.subheadline).frame(minHeight: 44)
                        }
                        Toggle("Remember email", isOn: $rememberEmail).font(.subheadline)
                        Text("Only your email is remembered here. Use iOS Passwords or your password manager to save your password.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if submitted && password.isEmpty {
                        AuthenticationNotice(message: "Enter your password to continue.")
                    } else if submitted && isRequestingAccess && !AuthenticationInput.isValidNewPassword(password) {
                        AuthenticationNotice(message: "Please meet the password requirements above. Long passphrases are welcome; include both letter cases, a number, and a symbol.")
                    }
                    if let error = store.errorMessage { AuthenticationNotice(message: error) }

                    Button(action: submit) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? (isRequestingAccess ? "Creating account…" : "Signing in…") : (isRequestingAccess ? "Create Account & Request Access" : "Sign In"))
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonStyle(.borderedProminent).disabled(busy)

                    if !isRequestingAccess {
                        Button("Need to verify your email?") {
                            store.clearAuthenticationMessages()
                            activeVerification = VerificationRequest(email: normalizedEmail, purpose: .signup)
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                    Label("Email verification comes first. An administrator then reviews your request before monitoring data is available.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 500).padding(AppTheme.screenPadding).padding(.top, 28).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively).background(AppTheme.groupedBackground)
            .onAppear { if email.isEmpty && rememberEmail { email = savedEmail } }
            .onChange(of: emailFocused) { _, focused in
                if !focused && !email.isEmpty { emailWasEdited = true }
            }
            .onChange(of: rememberEmail) { _, remember in if !remember { savedEmail = "" } }
            .onChange(of: isRequestingAccess) {
                password = ""; confirmPassword = ""; submitted = false
                store.clearAuthenticationMessages()
            }
            .sheet(item: $activeVerification) { request in
                EmailVerificationView(store: store, email: request.email, purpose: request.purpose, emailAlreadySent: request.emailAlreadySent)
            }
        }
    }

    private func submit() {
        guard !busy else { return }
        submitted = true
        store.clearAuthenticationMessages()
        guard AuthenticationInput.isValidEmail(email), !password.isEmpty else { return }
        guard !isRequestingAccess || (AuthenticationInput.isValidNewPassword(password) && password == confirmPassword) else { return }
        emailFocused = false; passwordFocused = false; confirmationFocused = false
        Task {
            if isRequestingAccess {
                let succeeded = await store.signUp(email: normalizedEmail, password: password)
                guard succeeded else { return }
                password = ""; confirmPassword = ""; submitted = false
                rememberCurrentEmail()
                if !store.isAuthenticated {
                    activeVerification = VerificationRequest(email: normalizedEmail, purpose: .signup, emailAlreadySent: true)
                }
            } else {
                await store.signIn(email: normalizedEmail, password: password)
                if store.isAuthenticated { rememberCurrentEmail(); password = "" }
            }
        }
    }

    private func rememberCurrentEmail() { savedEmail = rememberEmail ? normalizedEmail : "" }
}

#Preview { AuthenticationView(store: MonitoringStore()) }
