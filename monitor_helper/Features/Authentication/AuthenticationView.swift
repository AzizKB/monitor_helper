//
//  AuthenticationView.swift
//  monitor_helper
//

import SwiftUI

struct AuthenticationView: View {
    @Bindable var store: MonitoringStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mode: AuthenticationMode = .signIn
    @AppStorage("authentication.rememberEmail") private var rememberEmail = true
    @AppStorage("authentication.savedEmail") private var savedEmail = ""
    @FocusState private var focusedField: Field?

    private enum AuthenticationMode: Hashable {
        case signIn
        case signUp

        var title: String {
            switch self {
            case .signIn:
                return "Sign In"
            case .signUp:
                return "Request Access"
            }
        }

        var buttonTitle: String {
            switch self {
            case .signIn:
                return "Sign In"
            case .signUp:
                return "Create Account"
            }
        }
    }

    private enum Field {
        case email
        case password
        case confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "eye")
                        .font(.largeTitle)
                        .foregroundStyle(AppTheme.accent)

                    Text("monitor_helper")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("Secure mobile monitoring for approved beta users.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Authentication Mode", selection: $mode) {
                    Text("Sign In").tag(AuthenticationMode.signIn)
                    Text("Request Access").tag(AuthenticationMode.signUp)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .focused($focusedField, equals: .password)
                            .submitLabel(mode == .signIn ? .go : .next)
                            .onSubmit {
                                if mode == .signIn {
                                    signIn()
                                } else {
                                    focusedField = .confirmPassword
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                        if mode == .signUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .submitLabel(.go)
                                .onSubmit {
                                    signUp()
                                }
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Toggle(isOn: $rememberEmail) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remember email")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Password stays with iOS Keychain or your password manager.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(mode == .signUp)

                    Button {
                        // Future SSO will be implemented after the basic email/password flow is stable.
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.key")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign in with SSO")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Planned for a future release")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("Later")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }

                if let signUpMessage = store.signUpMessage {
                    Label(signUpMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    switch mode {
                    case .signIn:
                        signIn()
                    case .signUp:
                        signUp()
                    }
                } label: {
                    HStack {
                        if isBusy {
                            ProgressView()
                        }

                        Text(buttonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Text("New beta accounts must confirm email and be manually approved in Supabase before monitoring data is visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(AppTheme.screenPadding)
            .background(AppTheme.groupedBackground)
            .onAppear {
                guard email.isEmpty, rememberEmail else { return }
                email = savedEmail
                focusedField = savedEmail.isEmpty ? .email : .password
            }
            .onChange(of: rememberEmail) { _, newValue in
                if !newValue {
                    savedEmail = ""
                }
            }
            .onChange(of: mode) {
                confirmPassword = ""
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBusy: Bool {
        store.isSigningIn || store.isSigningUp
    }

    private var buttonTitle: String {
        if store.isSigningIn {
            return "Signing In"
        }

        if store.isSigningUp {
            return "Creating Account"
        }

        return mode.buttonTitle
    }

    private var canSubmit: Bool {
        guard !normalizedEmail.isEmpty, !password.isEmpty, !isBusy else {
            return false
        }

        switch mode {
        case .signIn:
            return true
        case .signUp:
            return password.count >= 8 && password == confirmPassword
        }
    }

    private func signIn() {
        guard mode == .signIn, canSubmit else { return }

        Task {
            await store.signIn(email: normalizedEmail, password: password)

            guard store.isAuthenticated else { return }

            if rememberEmail {
                savedEmail = normalizedEmail
            } else {
                savedEmail = ""
            }
        }
    }

    private func signUp() {
        guard mode == .signUp, canSubmit else { return }

        Task {
            await store.signUp(email: normalizedEmail, password: password)
            password = ""
            confirmPassword = ""
        }
    }
}

#Preview {
    AuthenticationView(store: MonitoringStore())
}
