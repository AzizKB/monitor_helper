//
//  MonitoringTimeRange.swift
//  monitor_helper
//

import Foundation

enum MonitoringTimeRange: String, CaseIterable, Identifiable {
    case fifteenMinutes = "15M"
    case thirtyMinutes = "30M"
    case oneHour = "1H"
    case threeHours = "3H"
    case sixHours = "6H"
    case twelveHours = "12H"
    case twentyFourHours = "24H"

    var id: String { rawValue }

    var hours: Int {
        switch self {
        case .fifteenMinutes, .thirtyMinutes:
            return 0
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

    var minutes: Int {
        switch self {
        case .fifteenMinutes:
            return 15
        case .thirtyMinutes:
            return 30
        default:
            return hours * 60
        }
    }

    var displayName: String {
        "Last \(rawValue)"
    }
}
