//
//  HealthBadge.swift
//  monitor_helper
//

import SwiftUI

struct HealthBadge: View {
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .imageScale(.small)

            Text(status.rawValue)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(HealthStatus.allCases) { status in
            HealthBadge(status: status)
        }
    }
    .padding()
}
