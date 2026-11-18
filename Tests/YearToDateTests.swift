import XCTest

/// Home's "This year" from January 1, and GitHub's last 12 months in the year sheet.
final class YearToDateTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter

    private func snapshot(endingOn end: String, days: Int, count: Int?, total: Int = 999) -> ContributionSnapshot {
        ContributionSnapshot(
            totalContributions: total,
            recentLevels: Array(repeating: 1, count: days),
            lastDate: end,
            fetchedAt: formatter.date(from: end)!,
            recentCounts: count.map { Array(repeating: $0, count: days) }
        )
    }

    // MARK: - January 1 to today

    func testThisYearCountsFromJanuaryFirst() {
        // January 31 + February 28 + March 1 to 4 is 63 days.
        let data = snapshot(endingOn: "2026-03-04", days: 371, count: 1)
        XCTAssertEqual(data.yearToDateTotal, 63)
    }

    func testThisYearSkipsLastYearsDays() {
        let data = snapshot(endingOn: "2026-01-02", days: 371, count: 5)
        XCTAssertEqual(data.yearToDateTotal, 10)
    }

    func testOldDataWithoutCountsKeepsTheTwelveMonthTotal() {
        let data = snapshot(endingOn: "2026-03-04", days: 371, count: nil, total: 1234)
        XCTAssertEqual(data.yearToDateTotal, 1234)
    }

    func testDataShortOfJanuaryFirstKeepsTheTwelveMonthTotal() {
        // 364 days back from December 31 starts on January 2.
        let data = snapshot(endingOn: "2026-12-31", days: 364, count: 1, total: 1234)
        XCTAssertEqual(data.yearToDateTotal, 1234)
    }

    // MARK: - Last 12 months

    func testLastTwelveMonthsSumsAYearBackFromTheLastDay() throws {
        let data = snapshot(endingOn: "2026-11-18", days: 371, count: 2)
        let summary = try XCTUnwrap(YearSummary(lastTwelveMonthsOf: data, today: formatter.date(from: "2026-11-18")!))

        // November 19, 2025 to November 18, 2026 is 365 days.
        XCTAssertTrue(summary.isRolling)
        XCTAssertEqual(summary.total, 730)
        XCTAssertEqual(summary.activeDays, 365)
        XCTAssertEqual(summary.longestRun, 365)

        // Thirteen bars, from a partial November 2025 to a partial November 2026.
        XCTAssertEqual(summary.months.count, 13)
        XCTAssertEqual(summary.months.first.map { [$0.year, $0.month] }, [2025, 11])
        XCTAssertEqual(summary.months.last.map { [$0.year, $0.month] }, [2026, 11])
        XCTAssertEqual(summary.months.first?.total, 24)
        XCTAssertEqual(summary.months.last?.total, 36)
        XCTAssertEqual(Set(summary.months.map(\.id)).count, 13)

        // December 2025 is the first 31-day month, so it wins the tie.
        XCTAssertEqual(summary.busiestMonth, 12)
        XCTAssertEqual(summary.busiestMonthYear, 2025)
    }

    func testLastTwelveMonthsNeedsDailyCounts() {
        let data = snapshot(endingOn: "2026-11-18", days: 371, count: nil)
        XCTAssertNil(YearSummary(lastTwelveMonthsOf: data))
    }

    func testCalendarYearsAreNotRolling() {
        let summary = YearSummary(ContributionYear(year: 2025, days: []), today: formatter.date(from: "2026-11-18")!)
        XCTAssertFalse(summary.isRolling)
        XCTAssertEqual(summary.months.map(\.year), Array(repeating: 2025, count: 12))
    }
}
