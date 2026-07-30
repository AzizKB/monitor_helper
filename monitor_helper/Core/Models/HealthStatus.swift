//
//  HealthStatus.swift
//  monitor_helper
//

import SwiftUI

enum HealthStatus: String, CaseIterable, Identifiable, Hashable {
    case critical = "Critical"
    case warning = "Warning"
    case healthy = "Healthy"
    case noData = "No Data"

    var id: String { rawValue }

    init(apiValue: String?) {
        switch apiValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical":
            self = .critical
        case "warning":
            self = .warning
        case "healthy":
            self = .healthy
        default:
            self = .noData
        }
    }

    var color: Color {
        switch self {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .healthy:
            return .green
        case .noData:
            return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .healthy:
            return "checkmark.circle.fill"
        case .noData:
            return "questionmark.circle.fill"
        }
    }

    var sortPriority: Int {
        switch self {
        case .critical:
            return 0
        case .warning:
            return 1
        case .healthy:
            return 2
        case .noData:
            return 3
        }
    }
}
