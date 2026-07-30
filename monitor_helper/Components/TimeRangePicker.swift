//
//  TimeRangePicker.swift
//  monitor_helper
//

import SwiftUI

struct TimeRangePicker: View {
    @Binding var selection: MonitoringTimeRange

    var body: some View {
        Menu {
            Picker("Time Range", selection: $selection) {
                ForEach(MonitoringTimeRange.allCases) { range in
                    Text(range.displayName)
                        .tag(range)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)

                Text(selection.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.accent.opacity(0.1))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Monitoring time range")
    }
}

#Preview {
    @Previewable @State var range: MonitoringTimeRange = .oneHour

    TimeRangePicker(selection: $range)
        .padding()
}
