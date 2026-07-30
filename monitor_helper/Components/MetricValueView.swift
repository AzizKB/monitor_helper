//
//  MetricValueView.swift
//  monitor_helper
//

import SwiftUI

struct MetricValueView: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 14)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, alignment: .topLeading)
    }
}

#Preview {
    HStack {
        MetricValueView(title: "Average Response Time", value: "144 ms", symbolName: "timer")
        MetricValueView(title: "Calls per Minute", value: "4,200", symbolName: "arrow.left.arrow.right")
        MetricValueView(title: "Errors per Minute", value: "0.2", symbolName: "xmark.octagon")
    }
    .padding()
}
