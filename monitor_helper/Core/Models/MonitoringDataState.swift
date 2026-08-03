//
//  MonitoringDataState.swift
//  monitor_helper
//

import Foundation

enum MonitoringDataState: Equatable {
    case initial
    case loading
    case live
    case cached(lastUpdated: Date)
    case empty
    case failed(message: String)

    var isUsingLiveData: Bool {
        if case .live = self {
            return true
        }

        return false
    }
}
