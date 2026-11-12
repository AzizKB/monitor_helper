import Foundation
import Testing
@testable import monitor_helper

@MainActor
struct InfrastructureSummaryTests {
    @Test func cachedNodesExpireWhenTheyStopReportingAndCanReturn() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let node = makeNode(lastUpdatedAt: now)
        #expect(node.isReporting(asOf: now.addingTimeInterval(65 * 60)))
        #expect(!node.isReporting(asOf: now.addingTimeInterval(65 * 60 + 1)))
        #expect(makeNode(lastUpdatedAt: now.addingTimeInterval(66 * 60)).isReporting(asOf: now.addingTimeInterval(66 * 60)))
    }

    @Test func nodesWithoutMetricsAreNotShownAsLive() {
        #expect(!makeNode(lastUpdatedAt: nil).isReporting())
    }

    private func makeNode(lastUpdatedAt: Date?) -> NodeSnapshot {
        NodeSnapshot(id: UUID(), applicationID: UUID(), tierName: "Tier", nodeName: "Node", health: .healthy, cpuPercent: nil, memoryPercent: nil, availabilityPercent: nil, lastUpdatedAt: lastUpdatedAt)
    }

    @Test func reportedNodesStaySeparateFromVisibleInventory() throws {
        let dto = try decodeSummary(reporting: "107")
        let application = SupabaseModelMapper.application(from: dto)
        #expect(application.totalNodes == 290)
        #expect(application.nodesReporting == 107)
        #expect(application.nodeSummary == "107/290 nodes")
    }

    @Test func zeroReportingDoesNotFallBackToInventoryCount() throws {
        let application = SupabaseModelMapper.application(from: try decodeSummary(reporting: "0"))
        #expect(application.nodeSummary == "0/290 nodes")
    }

    @Test func unknownReportingCountIsNotInvented() throws {
        let application = SupabaseModelMapper.application(from: try decodeSummary(reporting: "null"))
        #expect(application.nodesReporting == nil)
        #expect(application.totalNodes == 290)
    }

    private func decodeSummary(reporting: String) throws -> SupabaseMonitorApplicationDTO {
        let json = """
        {"application_id":"05bd8c2b-4915-4292-862f-99fc4895d125","application_name":"CRM","node_count":290,"nodes_reporting":\(reporting)}
        """
        return try JSONDecoder().decode(SupabaseMonitorApplicationDTO.self, from: Data(json.utf8))
    }
}
