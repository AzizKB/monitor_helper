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
    @State private var needsForegroundAccessCheck = false
    @Environment(\.scenePhase) private var scenePhase

    private var concealMonitoring: Bool {
        store.canAccessMonitoring && (scenePhase != .active || needsForegroundAccessCheck)
    }

    var body: some View {
        ZStack {
            if store.canAccessMonitoring {
                MonitorTabView(store: store)
                    .accessibilityHidden(concealMonitoring)
            } else if store.isAuthenticated && shouldShowAccessCheck {
                AccessCheckingView(store: store)
            } else if store.isAuthenticated {
                PendingAccessView(store: store)
            } else {
                AuthenticationView(store: store)
            }
            if concealMonitoring {
                AppTheme.groupedBackground.ignoresSafeArea()
                    .overlay {
                        if scenePhase == .active { ProgressView("Checking access…") }
                    }
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
                guard !Task.isCancelled else { return }
                await store.refresh()
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.automaticRefreshInterval)
                guard !Task.isCancelled else { return }
                await store.recheckAccessIfNeeded()
                await store.refreshIfNeeded(maxAge: 300)
            }
        }
        .task(id: store.canAccessMonitoring && scenePhase == .active) {
            guard store.canAccessMonitoring, scenePhase == .active else { return }
            await store.listenForSyncCompletions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { needsForegroundAccessCheck = store.isAuthenticated }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, needsForegroundAccessCheck else { return }
            await store.refreshMobileAccessStatus()
            guard !Task.isCancelled else { return }
            needsForegroundAccessCheck = false
            await store.refreshIfNeeded(maxAge: Self.foregroundRefreshMaxAge)
        }
    }

    private var shouldShowAccessCheck: Bool {
        store.isCheckingAccess || store.accessStatus.decision == .unknown
    }
}

#Preview {
    ContentView()
}
