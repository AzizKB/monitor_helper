//
//  SummaryTileView.swift
//  monitor_helper
//

import SwiftUI

struct SummaryTileView: View {
    let title: String
    let value: String
    let symbolName: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                Spacer()
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(AppTheme.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    SummaryTileView(title: "Critical Applications", value: "4", symbolName: "exclamationmark.triangle.fill", tint: .red)
        .padding()
        .background(AppTheme.groupedBackground)
}
