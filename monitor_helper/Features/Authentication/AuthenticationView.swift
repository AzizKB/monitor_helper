//
//  AuthenticationView.swift
//  monitor_helper
//

import SwiftUI

struct AuthenticationView: View {
    @Bindable var store: MonitoringStore
    @State private var email = ""
    @State private var password = ""
    @AppStorage("authentication.rememberEmail") private var rememberEmail = true
    @AppStorage("authentication.savedEmail") private var savedEmail = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
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

                    Text("Sign in to view live AppDynamics monitoring data from Supabase.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                signIn()
                            }
                            .textFieldStyle(.roundedBorder)
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

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    signIn()
                } label: {
                    HStack {
                        if store.isSigningIn {
                            ProgressView()
                        }

                        Text(store.isSigningIn ? "Signing In" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSignIn)

                Text("The iOS app uses the Supabase publishable key and an authenticated user session. It never uses service-role credentials.")
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
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSignIn: Bool {
        !normalizedEmail.isEmpty && !password.isEmpty && !store.isSigningIn
    }

    private func signIn() {
        guard canSignIn else { return }

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
}

#Preview {
    AuthenticationView(store: MonitoringStore())
}
