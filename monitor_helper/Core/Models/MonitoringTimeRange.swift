//
//  MonitoringTimeRange.swift
//  monitor_helper
//

import Foundation

enum MonitoringTimeRange: String, CaseIterable, Identifiable {
    case oneHour = "1H"
    case threeHours = "3H"
    case sixHours = "6H"
    case twelveHours = "12H"
    case twentyFourHours = "24H"

    var id: String { rawValue }

    var hours: Int {
        switch self {
        case .oneHour:
            return 1
        case .threeHours:
            return 3
        case .sixHours:
            return 6
        case .twelveHours:
            return 12
        case .twentyFourHours:
            return 24
        }
    }

    var displayName: String {
        "Last \(rawValue)"
    }
}
