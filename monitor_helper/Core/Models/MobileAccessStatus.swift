//
//  MobileAccessStatus.swift
//  monitor_helper
//

import Foundation

enum MobileAccessDecision: String, Codable {
    case pending
    case approved
    case blocked
    case unknown

    var displayName: String {
        switch self {
        case .pending:
            return "Pending Approval"
        case .approved:
            return "Approved"
        case .blocked:
            return "Access Blocked"
        case .unknown:
            return "Checking Access"
        }
    }
}

struct MobileAccessStatus: Equatable {
    let userID: UUID?
    let email: String?
    let decision: MobileAccessDecision
    let role: String?
    let requestedAt: Date?
    let approvedAt: Date?

    static let unknown = MobileAccessStatus(
        userID: nil,
        email: nil,
        decision: .unknown,
        role: nil,
        requestedAt: nil,
        approvedAt: nil
    )

    var isApproved: Bool {
        decision == .approved
    }

    var isPending: Bool {
        decision == .pending || decision == .unknown
    }
}
