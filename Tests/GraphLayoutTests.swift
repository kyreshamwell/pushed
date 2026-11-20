import SwiftUI
import WidgetKit
import XCTest

/// The 1.3 widget: squares that fill the frame, Large's two rows and labels,
/// the header's words and the Marks symbols.
final class GraphLayoutTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    /// A widget on a 6.9" iPhone, less its 16pt margins.
    private func inner(_ family: WidgetFamily) -> CGSize {
        let size = WidgetPreviewCard.size(for: family)
        return CGSize(width: size.width - 32, height: size.height - 32)
    }

    private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

    // MARK: - Filling the frame

    func testSmallFitsNineWeeksOfTwelvePointSquares() {
        let plan = GraphLayout(family: .systemSmall, size: inner(.systemSmall))
        XCTAssertEqual(plan.header, 22)
        XCTAssertEqual(plan.headerGap, 10)
        XCTAssertEqual(plan.fit.cell, 12)
        XCTAssertEqual(plan.weeks, 9)
        XCTAssertEqual(plan.bands, 1)
        XCTAssertFalse(plan.labels, "only Large has month and day names")
    }

    func testMediumFitsTwentyTwoWeeks() {
        let plan = GraphLayout(family: .systemMedium, size: inner(.systemMedium))
        XCTAssertEqual(plan.fit.cell, 12)
        XCTAssertEqual(plan.weeks, 22)
        XCTAssertFalse(plan.labels)
    }

    func testLargeShowsFortyWeeksInTwoLabeledRows() {
        let plan = GraphLayout(family: .systemLarge, size: inner(.systemLarge))
        XCTAssertEqual(plan.header, 88)
        XCTAssertEqual(plan.headerGap, 12)
        XCTAssertEqual(plan.bands, 2)
        XCTAssertEqual(plan.bandGap, 14)
        XCTAssertEqual(plan.fit.cell, 12)
        XCTAssertEqual(plan.fit.columns, 20)
        XCTAssertEqual(plan.weeks, 40)
        XCTAssertTrue(plan.labels)
    }

    func testTheSquaresMeetEveryEdge() {
        // 6.9" and 6.1" iPhones.
        let sizes: [(WidgetFamily, CGSize)] = families.map { ($0, inner($0)) } + [
            (.systemSmall, CGSize(width: 126, height: 126)),
            (.systemMedium, CGSize(width: 306, height: 126)),
            (.systemLarge, CGSize(width: 306, height: 322)),
        ]
        for (family, size) in sizes {
            let plan = GraphLayout(family: family, size: size)
            let labelWidth: CGFloat = plan.labels ? GraphLayout.dayColumn + GraphLayout.dayGap : 0
            let labelHeight: CGFloat = plan.labels ? GraphLayout.monthRow + GraphLayout.monthGap : 0
            XCTAssertEqual(plan.fit.width + labelWidth, size.width, accuracy: 0.001, "\(family) \(size) across")
            let height = plan.header + plan.headerGap
                + CGFloat(plan.bands) * (plan.fit.height + labelHeight)
                + CGFloat(plan.bands - 1) * plan.bandGap
            XCTAssertEqual(height, size.height, accuracy: 0.001, "\(family) \(size) down")

            // Gaps only ever stretch, and never by as much as another square.
            XCTAssertGreaterThanOrEqual(plan.fit.columnGap, GridFit.gap)
            XCTAssertGreaterThanOrEqual(plan.fit.rowGap, GridFit.gap)
            XCTAssertLessThan(plan.fit.columnGap, GridFit.gap + plan.fit.cell)
            XCTAssertLessThanOrEqual(plan.fit.rowGap, GridFit.gap + 7.0 / 6, "rows only take up the rounding")
            XCTAssertEqual(plan.fit.cell, plan.fit.cell.rounded(), "whole-point squares")
        }
    }

    func testTheLastSquareEndsAtTheRightEdge() {
        let fit = GridFit(width: 332, height: 106)
        XCTAssertEqual(fit.frame(column: fit.columns - 1, row: 6).maxX, 332, accuracy: 0.001)
        XCTAssertEqual(fit.frame(column: 0, row: 6).maxY, 106, accuracy: 0.001)
        XCTAssertEqual(fit.frame(index: 7 * 3 + 2), fit.frame(column: 3, row: 2))
    }

    func testWiderSpacingMeansSmallerSquaresStillFillingTheWidth() {
        let tight = GridFit(width: 332, height: 106, gap: GridFit.gap * SpacingChoice.tight.scale)
        let roomy = GridFit(width: 332, height: 106, gap: GridFit.gap * SpacingChoice.roomy.scale)
        XCTAssertGreaterThan(tight.cell, roomy.cell)
        XCTAssertEqual(tight.width, 332, accuracy: 0.001)
        XCTAssertEqual(roomy.width, 332, accuracy: 0.001)
    }

    func testWithoutLabelsLargeGivesTheirRoomToTheSquares() {
        let labeled = GraphLayout(family: .systemLarge, size: inner(.systemLarge))
        let minimal = GraphLayout(family: .systemLarge, size: inner(.systemLarge), labels: false)
        XCTAssertFalse(minimal.labels)
        XCTAssertGreaterThanOrEqual(minimal.fit.cell, labeled.fit.cell)
        XCTAssertEqual(minimal.fit.width, inner(.systemLarge).width, accuracy: 0.001)
    }

    func testARowOfSquaresFillsItsWidth() {
        let row = RowFit(width: 332, count: 7, gap: 8)
        XCTAssertEqual(row.cell, 40)
        XCTAssertEqual(row.size.width, 332, accuracy: 0.001)
        XCTAssertEqual(row.frame(6).maxX, 332, accuracy: 0.001)

        let capped = RowFit(width: 332, count: 7, gap: 8, maxCell: 30)
        XCTAssertEqual(capped.cell, 30)
        XCTAssertEqual(capped.size.width, 332, accuracy: 0.001, "the gaps take up the rest")
    }

    // MARK: - Rows of weeks

    func testTheBottomRowEndsTodayAndTheTopRowComesBeforeIt() {
        // Tuesday 17 November 2026.
        let now = date("2026-11-17")
        let history = ContributionSnapshot.sample(asOf: now).history(asOf: now)
        let bands = history.bands(2, weeks: 20)

        XCTAssertEqual(bands.count, 2)
        XCTAssertEqual(bands[0].days.count, 20 * 7, "the top row is whole weeks")
        XCTAssertEqual(bands[1].days.count, 19 * 7 + 3, "the bottom row stops at Tuesday")
        XCTAssertNil(bands[0].today)
        XCTAssertEqual(bands[1].today, bands[1].days.count - 1)
        XCTAssertEqual(
            (bands[0].days + bands[1].days).compactMap { $0 },
            Array(history.days.suffix(39 * 7 + 3)),
            "the rows run on from one to the next"
        )
        XCTAssertEqual(bands[1].start, date("2026-07-05"))
        XCTAssertEqual(bands[0].start, date("2026-02-15"))
        for band in bands {
            XCTAssertEqual(cal.component(.weekday, from: band.start!), 1, "every row starts on a Sunday")
        }
    }

    func testTodaySitsInTheLastWeekOnItsOwnWeekday() throws {
        // Sunday 15 through Saturday 21 November.
        for day in 15...21 {
            let now = date("2026-11-\(day)")
            let history = ContributionSnapshot.sample(asOf: now).history(asOf: now)
            let band = history.bands(1, weeks: 22)[0]
            let today = try XCTUnwrap(band.today)
            XCTAssertEqual(today, band.days.count - 1, "Nov \(day)")
            XCTAssertEqual(today / 7, 21, "today is in the last week")
            XCTAssertEqual(today % 7, cal.component(.weekday, from: now) - 1, "and on its weekday's row")
        }
    }

    func testADaysOldSnapshotStillEndsToday() {
        // Fetched on Tuesday the 10th, drawn a week later.
        let snapshot = ContributionSnapshot.sample(asOf: date("2026-11-10"))
        let history = snapshot.history(asOf: date("2026-11-17"))
        let band = history.bands(1, weeks: 9)[0]
        XCTAssertEqual(band.today, band.days.count - 1)
        XCTAssertEqual(band.days.count % 7, 3)
        XCTAssertEqual(band.days.suffix(7).map { $0?.level ?? -1 }, [0, 0, 0, 0, 0, 0, 0], "the week since counts as empty")
    }

    func testWeeksBeforeTheHistoryAreBlank() {
        let snapshot = ContributionSnapshot(
            totalContributions: 9, recentLevels: Array(repeating: 1, count: 10), lastDate: "2026-11-17", fetchedAt: Date()
        )
        let band = snapshot.history(asOf: date("2026-11-17")).bands(1, weeks: 9)[0]
        XCTAssertEqual(band.days.count, 8 * 7 + 3)
        XCTAssertEqual(band.days.prefix(7 * 7).compactMap { $0 }.count, 0)
        XCTAssertEqual(band.days.suffix(10).compactMap { $0 }.count, 10)
        XCTAssertEqual(band.today, band.days.count - 1)
    }

    func testWhenGitHubRunsAheadTodayIsntTheLastSquare() {
        // GitHub already says Wednesday; the phone still says Tuesday.
        let snapshot = ContributionSnapshot.sample(asOf: date("2026-11-18"))
        let band = snapshot.history(asOf: date("2026-11-17")).bands(1, weeks: 9)[0]
        XCTAssertEqual(band.today, band.days.count - 2)
        XCTAssertTrue(band.isAfterToday(band.days.count - 1))
        XCTAssertFalse(band.isAfterToday(band.days.count - 2))
    }

    func testAnEmptyHistoryStillDrawsItsWeeks() {
        let empty = ContributionSnapshot(totalContributions: 0, recentLevels: [], lastDate: "", fetchedAt: Date())
        let bands = empty.history().bands(2, weeks: 20)
        XCTAssertEqual(bands.map(\.days.count), [140, 140])
        XCTAssertNil(bands[1].today)
        XCTAssertTrue(bands[0].monthLabels().isEmpty)
    }

    func testTodaysRingSitsClearOfItsSquareInsideTheMargin() {
        let square = CGRect(x: 320, y: 94, width: 12, height: 12)
        for style in WidgetStyle.builtIn {
            let ring = DayPainter(theme: style.theme(for: .dark), mark: .ring).ring(around: square)
            // The ring's center line is 2.25pt out, so its outer edge is 3pt
            // out: well inside the 16pt margin, never clipped.
            XCTAssertEqual(ring.boundingRect.minX, square.minX - 2.25, accuracy: 0.01, "\(style)")
            XCTAssertEqual(ring.boundingRect.maxX, square.maxX + 2.25, accuracy: 0.01, "\(style)")
            XCTAssertEqual(ring.boundingRect.maxY, square.maxY + 2.25, accuracy: 0.01, "\(style)")
        }
    }

    // MARK: - Month names

    func testMonthNamesSitOverTheWeekEachMonthStarts() {
        let now = date("2026-11-17")
        let bands = ContributionSnapshot.sample(asOf: now).history(asOf: now).bands(2, weeks: 20)
        XCTAssertEqual(bands[1].monthLabels(), [
            MonthLabel(week: 0, text: "Jul"),
            MonthLabel(week: 4, text: "Aug"),
            MonthLabel(week: 9, text: "Sep"),
            MonthLabel(week: 13, text: "Oct"),
            MonthLabel(week: 17, text: "Nov"),
        ])
        // February's last two weeks lead the top row, too close to March to
        // fit a name, so it's left off.
        XCTAssertEqual(bands[0].monthLabels(), [
            MonthLabel(week: 2, text: "Mar"),
            MonthLabel(week: 7, text: "Apr"),
            MonthLabel(week: 11, text: "May"),
            MonthLabel(week: 16, text: "Jun"),
        ])
    }

    // MARK: - Marks

    func testMarksGiveEveryKindOfDayItsSymbol() {
        XCTAssertEqual(DayMark(StreakDay(level: 3), isToday: false), .dot(level: 3))
        XCTAssertEqual(DayMark(StreakDay(level: 9), isToday: false), .dot(level: 4))
        XCTAssertEqual(DayMark(StreakDay(level: 2), isToday: true), .dot(level: 2), "pushed today")
        XCTAssertEqual(DayMark(StreakDay(level: 0), isToday: true), .open, "not yet: just the ring")
        XCTAssertEqual(DayMark(StreakDay(level: 0, off: .rest), isToday: true), .open)
        XCTAssertEqual(DayMark(StreakDay(level: 0, off: .freeze), isToday: false), .freeze)
        XCTAssertEqual(DayMark(StreakDay(level: 0, off: .rest), isToday: false), .rest)
        XCTAssertEqual(DayMark(StreakDay(level: 0), isToday: false), .missed(endedStreak: false))
        XCTAssertEqual(DayMark(StreakDay(level: 0, endedStreak: true), isToday: false), .missed(endedStreak: true))
        XCTAssertEqual(DayMark(nil, isToday: false), .blank, "before the history starts")
        XCTAssertEqual(DayMark(StreakDay(level: 0), isToday: false, isAfterToday: true), .blank)
    }

    func testMarksFollowTheSameRestDaysAndFreezesAsEveryLook() {
        // Two weeks to Saturday 17 October: weekends are rest days from the
        // 1st, Wednesday the 14th was frozen and Tuesday the 13th was missed.
        let snapshot = ContributionSnapshot(
            totalContributions: 20,
            recentLevels: [0, 1, 2, 3, 4, 1, 0, 0, 2, 0, 0, 3, 1, 0],
            lastDate: "2026-10-17",
            fetchedAt: Date()
        )
        let protection = StreakProtection(
            schedules: [.init(from: "2026-10-01", weekdays: [1, 7])],
            claims: ["2026-10-14": .freeze]
        )
        let history = snapshot.history(protection: protection, asOf: date("2026-10-17"))
        let band = history.bands(1, weeks: 2)[0]
        let marks = band.days.indices.map { DayMark(band.days[$0], isToday: $0 == band.today) }
        XCTAssertEqual(Array(marks.suffix(7)), [
            .rest, .dot(level: 2), .missed(endedStreak: false), .freeze, .dot(level: 3), .dot(level: 1), .open,
        ])
        XCTAssertEqual(marks[0], .rest)
        XCTAssertEqual(marks[4], .dot(level: 4))
    }

    // MARK: - The header's words

    func testTheHeaderLeadsWithTheChosenNumber() {
        // Tuesday, twelve days into a streak: Sunday to today this week.
        let now = date("2026-11-17")
        let snapshot = ContributionSnapshot.sample(streak: 12, asOf: now)
        let history = snapshot.history(asOf: now)
        let total = snapshot.totalContributions
        func lead(_ stat: WidgetStat) -> WidgetHeadline.Stat {
            WidgetHeadline(history: history, total: total, stat: stat).lead
        }

        XCTAssertEqual(lead(.streak), .init(value: "12", label: "day streak", shortLabel: "streak"))
        XCTAssertEqual(lead(.best), .init(value: "\(history.bestStreak)", label: "best streak", shortLabel: "best"))
        XCTAssertEqual(lead(.week), .init(value: "3", label: "days this week", shortLabel: "this week"))
        XCTAssertEqual(lead(.year), .init(value: total.formatted(), label: "this year", shortLabel: "this year"))
    }

    func testOneDayThisWeekIsSingular() {
        // Sunday, with today pushed.
        let now = date("2026-11-15")
        let history = ContributionSnapshot.sample(streak: 5, asOf: now).history(asOf: now)
        let headline = WidgetHeadline(history: history, total: 0, stat: .week)
        XCTAssertEqual(headline.lead.value, "1")
        XCTAssertEqual(headline.lead.label, "day this week")
    }

    func testLargeShowsTheTwoNumbersThatArentTheLead() {
        XCTAssertEqual(WidgetHeadline.others(for: .streak), [.best, .year], "best and this year, as designed")
        XCTAssertEqual(WidgetHeadline.others(for: .best), [.streak, .year])
        XCTAssertEqual(WidgetHeadline.others(for: .year), [.streak, .best])
        XCTAssertEqual(WidgetHeadline.others(for: .week), [.streak, .best])

        let now = date("2026-11-17")
        let history = ContributionSnapshot.sample(streak: 12, asOf: now).history(asOf: now)
        let headline = WidgetHeadline(history: history, total: 812, stat: .streak)
        XCTAssertEqual(headline.others.map(\.shortLabel), ["best", "this year"])
        XCTAssertEqual(headline.others.last?.value, 812.formatted())
    }

    func testTheStatusSaysWhetherTodayIsIn() {
        let now = date("2026-11-17")
        func status(_ snapshot: ContributionSnapshot, _ protection: StreakProtection = .none) -> String {
            WidgetHeadline(history: snapshot.history(protection: protection, asOf: now), total: 0, stat: .streak).status
        }
        XCTAssertEqual(status(.sample(asOf: now)), "Pushed today")
        XCTAssertEqual(status(.sample(quiet: 1, asOf: now)), "Not yet today")
        let restingTuesdays = StreakProtection(schedules: [.init(from: "2026-11-01", weekdays: [3])])
        XCTAssertEqual(status(.sample(quiet: 1, asOf: now), restingTuesdays), "Rest day")
        XCTAssertEqual(StreakHistory.Today.off(.freeze).status, "Streak frozen")
    }
}
