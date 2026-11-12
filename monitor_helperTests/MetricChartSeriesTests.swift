import Foundation
import Testing
@testable import monitor_helper

@MainActor
struct MetricChartSeriesTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func requestedResolutionMatchesEveryTimeRange() {
        for range in MonitoringTimeRange.allCases {
            let expected = range.minutes <= 180 ? 1 : 10
            #expect(range.chartIntervalMinutes == expected)
        }
        #expect(MonitoringTimeRange.sixHours.chartIntervalMinutes == 10)
    }

    @Test func chartDomainKeepsTheFullHourWhenLatestDataIsDelayed() {
        let points = (0..<55).map { point(minute: $0, value: 100) }
        let series = makeSeries(points: points, metric: .averageResponseTime)
        #expect(series.timeDomain.lowerBound == start)
        #expect(series.timeDomain.upperBound == start.addingTimeInterval(3600))
        #expect(series.latestPoint?.timestamp == start.addingTimeInterval(54 * 60))
    }

    @Test func missingMinutesBreakTheLineWithoutInventingZeroValues() {
        let series = makeSeries(points: [point(minute: 0, value: 10), point(minute: 1, value: 20), point(minute: 4, value: 30)], metric: .callsPerMinute)
        #expect(series.plottedPoints.map(\.segment) == [0, 0, 1])
        #expect(series.points.map(\.value) == [10, 20, 30])
    }

    @Test func responseAverageUsesObservationCountsRatherThanAveragingAverages() throws {
        var lowTraffic = point(minute: 0, value: 100, count: 1)
        lowTraffic.sumValue = 100
        var highTraffic = point(minute: 1, value: 10, count: 9)
        highTraffic.sumValue = 90
        let result = try #require(makeSeries(points: [lowTraffic, highTraffic], metric: .averageResponseTime).averageValue)
        #expect(abs(result - 19) < 0.000001)
    }

    @Test func rateAverageAccountsForPartiallyFilledBuckets() throws {
        var full = point(minute: 0, value: 10)
        full.sampleCount = 10
        var partial = point(minute: 10, value: 100)
        partial.sampleCount = 1
        let series = makeSeries(points: [full, partial], metric: .callsPerMinute, interval: 10)
        let result = try #require(series.averageValue)
        #expect(abs(result - 200.0 / 11.0) < 0.000001)
    }

    @Test func chartResponseDecodesWindowAndPeakWithoutUsingSourceMaximumAsObservedValue() throws {
        let json = """
        {"observed_at":"2026-11-11T08:00:00+00:00","value":55,"min_value":6,"max_value":8000,"count_value":4737,"sum_value":258872,"sample_count":10,"peak_value":93,"peak_observed_at":"2026-11-11T07:53:00+00:00","window_start":"2026-11-11T02:00:00+00:00","window_end":"2026-11-11T08:00:00+00:00","bucket_minutes":10}
        """
        let dto = try JSONDecoder().decode(SupabaseChartPointDTO.self, from: Data(json.utf8))
        let mapped = try #require(SupabaseModelMapper.chartPoint(from: dto))
        #expect(mapped.value == 55)
        #expect(mapped.maximumValue == 8000)
        #expect(mapped.peakValue == 93)
        #expect(mapped.sampleCount == 10)
        #expect(dto.bucketMinutes == 10)
        #expect(SupabaseDateParser.date(from: dto.windowStart) != nil)
    }

    private func point(minute: Int, value: Double, count: Int? = nil) -> LiveMetricChartPoint {
        LiveMetricChartPoint(timestamp: start.addingTimeInterval(Double(minute * 60)), value: value, currentValue: nil, minimumValue: nil, maximumValue: nil, countValue: count)
    }

    private func makeSeries(points: [LiveMetricChartPoint], metric: PerformanceMetric, interval: Int = 1) -> MetricChartSeries {
        MetricChartSeries(metric: metric, points: points, windowStart: start, windowEnd: start.addingTimeInterval(3600), intervalMinutes: interval)
    }
}
