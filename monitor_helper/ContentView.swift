//
//  ContentView.swift
//  monitor_helper
//
//  Created by Abdulaziz Bandar on 27/07/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var store = MonitoringStore()

    var body: some View {
        MonitorTabView(store: store)
            .task {
                await store.bootstrap()
            }
    }
}

#Preview {
    ContentView()
}
