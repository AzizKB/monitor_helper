//
//  ContentView.swift
//  monitor_helper
//
//  Created by Abdulaziz Bandar on 27/07/2026.
//

import SwiftUI

struct ContentView: View {
    private static let automaticRefreshInterval: Duration = .seconds(300)
    private static let foregroundRefreshMaxAge: TimeInterval = 60

    @State private var store = MonitoringStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.canAccessMonitoring {
                MonitorTabView(store: store)
            } else if store.isAuthenticated && shouldShowAccessCheck {
                AccessCheckingView(store: store)
            } else if store.isAuthenticated {
                PendingAccessView(store: store)
            } else {
                AuthenticationView(store: store)
            }
        }
        .task {
            await store.bootstrap()
        }
        .task(id: store.canAccessMonitoring) {
            guard store.canAccessMonitoring else { return }

            await store.refresh()
            if store.canAccessMonitoring && !store.isUsingLiveData {
                try? await Task.sleep(for: .seconds(3))
                await store.refresh()
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.automaticRefreshInterval)
                await store.refreshIfNeeded(maxAge: 300)
            }
        }
        .task(id: store.canAccessMonitoring) {
            guard store.canAccessMonitoring else { return }
            await store.listenForSyncCompletions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, store.isAuthenticated else { return }

            Task {
                await store.refreshMobileAccessStatus()
                await store.refreshIfNeeded(maxAge: Self.foregroundRefreshMaxAge)
            }
        }
    }

    private var shouldShowAccessCheck: Bool {
        store.isCheckingAccess || store.accessStatus.decision == .unknown
    }
}

#Preview {
    ContentView()
}
