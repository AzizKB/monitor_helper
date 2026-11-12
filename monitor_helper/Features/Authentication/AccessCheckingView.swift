//
//  AccessCheckingView.swift
//  monitor_helper
//

import SwiftUI

struct AccessCheckingView: View {
    @Bindable var store: MonitoringStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 32)

                VStack(alignment: .leading, spacing: 12) {
                    if store.isCheckingAccess {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "exclamationmark.shield")
                            .font(.system(size: 36)).foregroundStyle(.orange)
                    }

                    Text(store.isCheckingAccess ? "Checking Access" : "Couldn't Check Access")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("We are confirming this account before loading monitoring data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !store.isCheckingAccess {
                    Button {
                        Task {
                            await store.refreshMobileAccessStatus()
                        }
                    } label: {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    store.signOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(AppTheme.screenPadding)
            .background(AppTheme.groupedBackground)
            .navigationTitle("Beta Access")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AccessCheckingView(store: MonitoringStore())
}
