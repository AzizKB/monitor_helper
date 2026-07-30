//
//  EventsDetailView.swift
//  monitor_helper
//

import SwiftUI

struct EventsDetailView: View {
    let application: ApplicationSnapshot

    var body: some View {
        List {
            Section {
                Label("Recent events will be loaded from Supabase after authentication is connected.", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        EventsDetailView(application: MockMonitoringData.applications[0])
    }
}
