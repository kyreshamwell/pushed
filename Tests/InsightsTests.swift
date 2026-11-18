import XCTest

/// The streak runs, year sums and the year cache behind the streak and year sheets.
final class InsightsTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    /// One character per day, oldest first: "#" pushed, "." empty. Spaces
    /// only separate weeks.
    private func snapshot(endingOn end: String, _ pattern: String, counts: [Int]? = nil) -> ContributionSnapshot {
        let levels = pattern.filter { $0 != " " }.map { $0 == "#" ? 2 : 0 }
        return ContributionSnapshot(
            totalContributions: levels.reduce(0, +),
            recentLevels: levels,
            lastDate: end,
            fetchedAt: date(end),
            recentCounts: counts
        )
    }

    private func resting(_ weekdays: Int..., claims: [String: DayOff] = [:]) -> StreakProtection {
        StreakProtection(schedules: [.init(from: "2026-01-01", weekdays: weekdays)], claims: claims)
    }

    // MARK: - The current run

    func testTheCurrentRunStartsOnItsFirstPushAndReachesToday() {
        // 2026-11-18 is a Wednesday. Pushed Sunday to today.
        let snap = snapshot(endingOn: "2026-11-18", "...#.#. ####")
        let history = snap.history(asOf: date("2026-11-18"))
        let run = try! XCTUnwrap(history.currentRun)
        XCTAssertEqual(run.length, 4)
        XCTAssertEqual(history.date(at: run.start), date("2026-11-15"))
        XCTAssertEqual(history.date(at: run.end), date("2026-11-18"))
    }

    func testAPendingTodayStaysInTheRun() {
        let snap = snapshot(endingOn: "2026-11-18", "..##.#. ###.")
        let history = snap.history(asOf: date("2026-11-18"))
        let run = try! XCTUnwrap(history.currentRun)
        XCTAssertEqual(run.length, 3)
        XCTAssertEqual(history.date(at: run.end), date("2026-11-18"))
    }

    func testRestDaysAndFreezesCarryTheRunAndAreCounted() {
        // Saturday 11-14 and Sunday 11-15 are rest days; Monday 11-16 frozen.
        let protection = resting(1, 7, claims: ["2026-11-16": .freeze])
        let snap = snapshot(endingOn: "2026-11-18", "..####. ..##", counts: [0, 0, 1, 2, 3, 4, 0, 0, 0, 5, 6])
        let history = snap.history(protection: protection, asOf: date("2026-11-18"))
        let run = try! XCTUnwrap(history.currentRun)
        XCTAssertEqual(run.length, 6)
        XCTAssertEqual(history.date(at: run.start), date("2026-11-10"))

        let stats = history.stats(of: run, counts: snap.recentCounts)
        XCTAssertEqual(stats.pushedDays, 6)
        XCTAssertEqual(stats.restDays, 2)
        XCTAssertEqual(stats.freezes, 1)
        XCTAssertEqual(stats.contributions, 21)
    }

    func testOffDaysBeforeTheFirstPushAreNotPartOfTheRun() {
        // Sunday 11-15 is a rest day before the run starts on Monday.
        let snap = snapshot(endingOn: "2026-11-18", "....... .###")
        let history = snap.history(protection: resting(1), asOf: date("2026-11-18"))
        let run = try! XCTUnwrap(history.currentRun)
        XCTAssertEqual(history.date(at: run.start), date("2026-11-16"))
        XCTAssertEqual(history.stats(of: run, counts: nil).restDays, 0)
    }

    func testNoCountsLeavesContributionsUnknown() {
        let snap = snapshot(endingOn: "2026-11-18", "...#.## ####")
        let history = snap.history(asOf: date("2026-11-18"))
        XCTAssertNil(history.stats(of: history.currentRun!, counts: nil).contributions)
    }

    func testABrokenStreakHasNoCurrentRun() {
        let snap = snapshot(endingOn: "2026-11-18", "..##### ##..")
        XCTAssertNil(snap.history(asOf: date("2026-11-18")).currentRun)
    }

    // MARK: - The best run

    func testTheBestRunMatchesBestStreakWithItsDates() {
        let snap = snapshot(endingOn: "2026-11-18", ".#####. ##.#")
        let history = snap.history(asOf: date("2026-11-18"))
        let best = try! XCTUnwrap(history.bestRun)
        XCTAssertEqual(best.length, history.bestStreak)
        XCTAssertEqual(best.length, 5)
        XCTAssertEqual(history.date(at: best.start), date("2026-11-09"))
        XCTAssertEqual(history.date(at: best.end), date("2026-11-13"))
    }

    func testATieGoesToTheLaterRun() {
        let snap = snapshot(endingOn: "2026-11-18", "###.... ###.")
        let history = snap.history(asOf: date("2026-11-18"))
        let best = try! XCTUnwrap(history.bestRun)
        XCTAssertEqual(best.length, 3)
        XCTAssertEqual(best.start, history.currentRun?.start)
        XCTAssertEqual(history.date(at: best.start), date("2026-11-15"))
    }

    func testTheBestRunAgreesWithBestStreakOnSampleData() {
        for streak in [0, 5, 12, 40] {
            let now = date("2026-11-18")
            let history = ContributionSnapshot.sample(streak: streak, asOf: now).history(asOf: now)
            XCTAssertEqual(history.bestRun?.length ?? 0, history.bestStreak, "streak \(streak)")
        }
    }

    func testNoPushesHasNoBestRun() {
        let snap = snapshot(endingOn: "2026-11-18", "....... ....")
        XCTAssertNil(snap.history(asOf: date("2026-11-18")).bestRun)
    }

    // MARK: - The calendar

    func testTheCalendarCoversEveryMonthOfTheRun() {
        // Pushed every day from Oct 28 through Nov 18.
        let pattern = String(repeating: ".", count: 10) + String(repeating: "#", count: 22)
        let snap = snapshot(endingOn: "2026-11-18", pattern)
        let history = snap.history(asOf: date("2026-11-18"))
        let months = history.calendarMonths(for: history.currentRun!)

        XCTAssertEqual(months.map(\.start), [date("2026-10-01"), date("2026-11-01")])
        // October 1, 2026 is a Thursday, so four blanks before it.
        XCTAssertEqual(months[0].leadingBlanks, 4)
        XCTAssertEqual(months[0].days.count, 31)

        let october = months[0].days
        XCTAssertFalse(october[26].inRun)
        XCTAssertTrue(october[27].inRun)
        XCTAssertEqual(october[27].kind, .pushed(level: 2))

        let november = months[1].days
        XCTAssertTrue(november[17].isToday)
        XCTAssertTrue(november[17].inRun)
        XCTAssertEqual(november[18].kind, .future)
        XCTAssertFalse(november[18].inRun)
    }

    func testTheCalendarMarksDaysOff() {
        let protection = resting(1, 7, claims: ["2026-11-16": .freeze])
        let snap = snapshot(endingOn: "2026-11-18", "..####. ..##")
        let history = snap.history(protection: protection, asOf: date("2026-11-18"))
        let days = history.calendarMonths(for: history.currentRun!)[0].days
        XCTAssertEqual(days[13].kind, .rest) // Saturday the 14th
        XCTAssertEqual(days[14].kind, .rest) // Sunday the 15th
        XCTAssertEqual(days[15].kind, .freeze) // Monday the 16th
        XCTAssertTrue(days[15].inRun)
    }

    // MARK: - Milestones

    func testTheNextMilestoneComesFromTheNotificationList() {
        XCTAssertEqual(StreakMilestone.next(after: 0), 3)
        XCTAssertEqual(StreakMilestone.next(after: 12), 14)
        XCTAssertEqual(StreakMilestone.next(after: 14), 30)
        XCTAssertNil(StreakMilestone.next(after: 365))
        XCTAssertEqual(StreakMilestone.progress(12), 12.0 / 14.0, accuracy: 0.0001)
        XCTAssertEqual(StreakMilestone.progress(400), 1)
    }

    // MARK: - Year sums

    private func year2025(_ days: [(String, Int)]) -> ContributionYear {
        ContributionYear(year: 2025, days: days.map { YearDay(date: $0.0, count: $0.1, level: $0.1 == 0 ? 0 : 1) })
    }

    func testAYearAddsUpItsDays() {
        let data = year2025([
            ("2025-01-01", 3), ("2025-01-02", 1), ("2025-01-03", 0), ("2025-01-04", 2),
            ("2025-03-10", 5), ("2025-03-11", 9), ("2025-03-12", 1), ("2025-03-13", 2),
            ("2025-12-31", 4),
        ])
        let summary = YearSummary(data, today: date("2026-06-01"))

        XCTAssertEqual(summary.total, 27)
        XCTAssertEqual(summary.activeDays, 8)
        XCTAssertEqual(summary.longestRun, 4)
        XCTAssertEqual(summary.busiestMonth, 3)
        XCTAssertEqual(summary.busiestDay, YearDay(date: "2025-03-11", count: 9, level: 1))
        XCTAssertEqual(summary.months.count, 12)

        let january = summary.months[0]
        XCTAssertEqual(january.total, 6)
        XCTAssertEqual(january.activeDays, 3)
        XCTAssertEqual(january.longestRun, 2)
        XCTAssertEqual(january.busiestDay?.date, "2025-01-01")
        XCTAssertEqual(january.days.count, 31)
        // January 1, 2025 is a Wednesday.
        XCTAssertEqual(january.leadingBlanks, 3)
        XCTAssertEqual(summary.months[1].days.count, 28)
        XCTAssertNil(summary.months[1].busiestDay)
        XCTAssertFalse(summary.months[11].isFuture)
    }

    func testARunCarriesAcrossMonthsForTheYearButNotTheMonth() {
        let data = year2025([("2025-01-30", 1), ("2025-01-31", 1), ("2025-02-01", 1), ("2025-02-02", 1)])
        let summary = YearSummary(data, today: date("2026-06-01"))
        XCTAssertEqual(summary.longestRun, 4)
        XCTAssertEqual(summary.months[0].longestRun, 2)
        XCTAssertEqual(summary.months[1].longestRun, 2)
    }

    func testADayLeftOutOfTheDataBreaksARun() {
        let data = year2025([("2025-05-01", 1), ("2025-05-02", 1), ("2025-05-04", 1)])
        XCTAssertEqual(YearSummary(data, today: date("2026-06-01")).longestRun, 2)
    }

    func testTiesKeepTheEarlierMonthAndDay() {
        let data = year2025([("2025-02-03", 4), ("2025-06-09", 4)])
        let summary = YearSummary(data, today: date("2026-06-01"))
        XCTAssertEqual(summary.busiestMonth, 2)
        XCTAssertEqual(summary.busiestDay?.date, "2025-02-03")
    }

    func testAnEmptyYearHasNoBusiestMonth() {
        let summary = YearSummary(year2025([]), today: date("2026-06-01"))
        XCTAssertEqual(summary.total, 0)
        XCTAssertNil(summary.busiestMonth)
        XCTAssertNil(summary.busiestDay)
        XCTAssertEqual(summary.longestRun, 0)
    }

    func testTheCurrentYearStopsAtToday() {
        let data = ContributionYear(year: 2026, days: [
            YearDay(date: "2026-11-17", count: 2, level: 1),
            YearDay(date: "2026-11-18", count: 3, level: 1),
            // GitHub's own clock can run a day ahead.
            YearDay(date: "2026-11-19", count: 7, level: 3),
        ])
        let summary = YearSummary(data, today: date("2026-11-18"))
        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.longestRun, 2)
        XCTAssertFalse(summary.months[10].isFuture)
        XCTAssertTrue(summary.months[11].isFuture)
        XCTAssertEqual(summary.months[11].total, 0)
    }

    func testOnlyTheYearsOwnDaysAreKept() {
        let calendar = ContributionCalendar(totalContributions: 3, days: [
            ContributionDay(date: "2024-12-31", contributionCount: 5, contributionLevel: "FOURTH_QUARTILE"),
            ContributionDay(date: "2025-01-01", contributionCount: 3, contributionLevel: "SECOND_QUARTILE"),
        ])
        let year = ContributionYear(year: 2025, calendar: calendar)
        XCTAssertEqual(year.days, [YearDay(date: "2025-01-01", count: 3, level: 2)])
    }

    // MARK: - The current year from the snapshot

    func testTheSnapshotGivesTheCurrentYearWithItsCounts() {
        let now = date("2026-11-18")
        let snap = ContributionSnapshot.sample(asOf: now)
        let year = try! XCTUnwrap(ContributionYear(snapshot: snap, year: 2026))
        XCTAssertEqual(year.days.first?.date, "2026-01-01")
        XCTAssertEqual(year.days.last?.date, "2026-11-18")
        XCTAssertEqual(year.days.last?.count, snap.recentCounts?.last)
        XCTAssertEqual(year.days.last?.level, snap.recentLevels.last)
    }

    func testASnapshotWithoutCountsOrJanuaryGivesNoYear() {
        let now = date("2026-11-18")
        var snap = ContributionSnapshot.sample(asOf: now)
        XCTAssertNil(ContributionYear(snapshot: snap, year: 2025), "the snapshot starts after January 1, 2025")
        snap.recentCounts = nil
        XCTAssertNil(ContributionYear(snapshot: snap, year: 2026))
    }

    func testSampleCountsMatchTheirLevels() {
        let snap = ContributionSnapshot.sample(asOf: date("2026-11-18"))
        let counts = try! XCTUnwrap(snap.recentCounts)
        XCTAssertEqual(counts.count, snap.recentLevels.count)
        XCTAssertEqual(counts.reduce(0, +), snap.totalContributions)
        for (level, count) in zip(snap.recentLevels, counts) {
            XCTAssertEqual(level == 0, count == 0)
        }
    }

    func testSampleYearsGetBusier() {
        let first = YearSummary(.sample(year: 2023, joinYear: 2023), today: date("2026-11-18"))
        let later = YearSummary(.sample(year: 2025, joinYear: 2023), today: date("2026-11-18"))
        XCTAssertGreaterThan(later.total, first.total)
        XCTAssertEqual(first.months[0].total, 0, "the account opens in March")
    }

    // MARK: - Parsing

    func testAYearResponseIsParsed() throws {
        let json = """
        {"data":{"user":{"contributionsCollection":{"contributionCalendar":{"totalContributions":4,"weeks":[
          {"contributionDays":[
            {"date":"2025-12-30","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"},
            {"date":"2025-12-31","contributionCount":3,"contributionLevel":"THIRD_QUARTILE"}
          ]}
        ]}}}}}
        """
        let year = try GitHubContributionsService.parseYear(Data(json.utf8), year: 2025)
        XCTAssertEqual(year.days.map(\.count), [1, 3])
        XCTAssertEqual(year.days.map(\.level), [1, 3])
    }

    func testTheJoinYearIsReadFromCreatedAt() throws {
        let json = #"{"data":{"user":{"createdAt":"2019-07-04T12:00:00Z"}}}"#
        XCTAssertEqual(try GitHubContributionsService.parseJoinYear(Data(json.utf8)), 2019)

        let missing = #"{"data":null,"errors":[{"type":"NOT_FOUND","message":"nope"}]}"#
        XCTAssertThrowsError(try GitHubContributionsService.parseJoinYear(Data(missing.utf8))) {
            XCTAssertEqual($0 as? GitHubServiceError, .userNotFound)
        }
    }

    // MARK: - The cache

    private func makeCache() -> YearHistoryCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YearHistoryCacheTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return YearHistoryCache(directory: directory)
    }

    func testAFinishedYearIsStoredAndReadBack() {
        let cache = makeCache()
        let data = ContributionYear.sample(year: 2024, joinYear: 2023)
        XCTAssertTrue(cache.save(data, for: "Octocat", asOf: date("2026-11-18")))
        XCTAssertEqual(cache.year(2024, for: "octocat"), data, "logins ignore case")
        XCTAssertNil(cache.year(2023, for: "octocat"))
        XCTAssertNil(cache.year(2024, for: "someone-else"))
    }

    func testTheCurrentYearIsNeverStored() {
        let cache = makeCache()
        let now = date("2026-11-18")
        XCTAssertFalse(cache.save(ContributionYear(year: 2026, days: []), for: "octocat", asOf: now))
        XCTAssertFalse(cache.save(ContributionYear(year: 2027, days: []), for: "octocat", asOf: now))
        XCTAssertNil(cache.year(2026, for: "octocat"))
    }

    func testTheJoinYearIsKeptPerAccountAndForgotten() {
        let cache = makeCache()
        XCTAssertNil(cache.joinYear(for: "octocat"))
        cache.saveJoinYear(2019, for: "octocat")
        XCTAssertEqual(cache.joinYear(for: "OctoCat"), 2019)
        XCTAssertNil(cache.joinYear(for: "hubot"))

        cache.save(ContributionYear(year: 2020, days: []), for: "octocat", asOf: date("2026-11-18"))
        cache.removeAll()
        XCTAssertNil(cache.joinYear(for: "octocat"))
        XCTAssertNil(cache.year(2020, for: "octocat"))
    }

    func testALoginCannotReachOutsideTheCache() {
        let cache = makeCache()
        XCTAssertTrue(cache.save(ContributionYear(year: 2020, days: []), for: "../../escape", asOf: date("2026-11-18")))
        let outside = cache.directory.deletingLastPathComponent().appendingPathComponent("escape")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertNotNil(cache.year(2020, for: "../../escape"))
    }
}
