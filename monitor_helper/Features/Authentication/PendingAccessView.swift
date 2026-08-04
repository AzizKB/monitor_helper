//
//  PendingAccessView.swift
//  monitor_helper
//

import SwiftUI

struct PendingAccessView: View {
    @Bindable var store: MonitoringStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 32)

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(store.accessStatus.decision.displayName)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SettingsLikeMetricRow(
                        title: "Account",
                        value: store.accessStatus.email ?? store.session?.userEmail ?? "Signed in",
                        symbolName: "person.crop.circle"
                    )

                    SettingsLikeMetricRow(
                        title: "Approval Status",
                        value: store.accessStatus.decision.displayName,
                        symbolName: "checkmark.seal"
                    )
                }
                .padding(16)
                .background(AppTheme.secondaryGroupedBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await store.refreshMobileAccessStatus()
                    }
                } label: {
                    HStack {
                        if store.isCheckingAccess {
                            ProgressView()
                        }

                        Text(store.isCheckingAccess ? "Checking" : "Check Approval")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isCheckingAccess)

                Button(role: .destructive) {
                    store.signOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("After an administrator approves this account in Supabase, tap Check Approval to enter the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(AppTheme.screenPadding)
            .background(AppTheme.groupedBackground)
            .navigationTitle("Beta Access")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusIcon: String {
        switch store.accessStatus.decision {
        case .pending, .unknown:
            return "clock.badge.questionmark"
        case .approved:
            return "checkmark.seal.fill"
        case .blocked:
            return "xmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch store.accessStatus.decision {
        case .pending, .unknown:
            return .orange
        case .approved:
            return .green
        case .blocked:
            return .red
        }
    }

    private var statusMessage: String {
        switch store.accessStatus.decision {
        case .pending:
            return "Your account was created successfully, but monitoring access is waiting for manual approval."
        case .approved:
            return "Your account is approved. The monitoring workspace is ready."
        case .blocked:
            return "This account is blocked. Contact the project administrator if this looks wrong."
        case .unknown:
            return "We are checking whether this account has beta access."
        }
    }
}

#Preview {
    PendingAccessView(store: MonitoringStore())
}
