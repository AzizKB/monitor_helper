//
//  AuthenticationView.swift
//  monitor_helper
//

import SwiftUI

struct AuthenticationView: View {
    @Bindable var store: MonitoringStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
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

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await store.signIn(email: email, password: password)
                    }
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
                .disabled(email.isEmpty || password.isEmpty || store.isSigningIn)

                Text("The iOS app uses the Supabase publishable key and an authenticated user session. It never uses service-role credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(AppTheme.screenPadding)
            .background(AppTheme.groupedBackground)
        }
    }
}

#Preview {
    AuthenticationView(store: MonitoringStore())
}
