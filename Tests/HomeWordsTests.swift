import XCTest

final class HomeWordsTests: XCTestCase {
    private func date(_ s: String) -> Date { ContributionCalendar.dateFormatter.date(from: s)! }

    func testTheCaptionNamesTodayAndTomorrow() {
        var library = StyleLibrary.starting()
        let day = date("2026-11-17")
        XCTAssertEqual(HomeWords.rotationCaption(library, on: day), "Classic")

        library.addToRotation(.builtIn(.aurora), on: day)
        XCTAssertEqual(HomeWords.rotationCaption(library, on: day), "Today Aurora")

        library.addToRotation(.builtIn(.ember), on: day)
        library.addToRotation(.builtIn(.paper), on: day)
        XCTAssertEqual(HomeWords.rotationCaption(library, on: day), "Today Aurora · Tomorrow Ember")
        XCTAssertEqual(HomeWords.rotationCaption(library, on: date("2026-11-19")), "Today Paper · Tomorrow Aurora")
    }

    func testTheStylesRowCountsTheRotation() {
        var library = StyleLibrary.starting()
        XCTAssertEqual(HomeWords.stylesSummary(library), "Nothing in rotation")
        library.addToRotation(.builtIn(.marks))
        XCTAssertEqual(HomeWords.stylesSummary(library), "1 look in rotation")
        library.addToRotation(.builtIn(.classic))
        XCTAssertEqual(HomeWords.stylesSummary(library), "2 looks in rotation")
    }

    func testTodaysCardSaysWhatHappened() {
        let pushed = ContributionSnapshot.sample(streak: 12).history()
        XCTAssertEqual(HomeWords.today(pushed, count: 3).title, "Pushed today")
        XCTAssertEqual(HomeWords.today(pushed, count: 3).detail, "3 contributions")
        XCTAssertEqual(HomeWords.today(pushed, count: 1).detail, "1 contribution")
        XCTAssertNil(HomeWords.today(pushed, count: nil).detail, "no count, no guess")

        let waiting = ContributionSnapshot.sample(streak: 12, quiet: 1).history()
        XCTAssertEqual(HomeWords.today(waiting, count: nil).title, "Not yet today")
        XCTAssertEqual(HomeWords.today(waiting, count: nil).kind, .pending)
    }

    func testTodaysCountOnlyComesFromTodaysData() {
        let now = Date()
        var snapshot = ContributionSnapshot.sample(streak: 12, asOf: now)
        let history = snapshot.history(asOf: now)
        XCTAssertNil(HomeWords.todayCount(snapshot, history: history, now: now), "data saved before 1.3")

        snapshot.lastDayCount = 4
        XCTAssertEqual(HomeWords.todayCount(snapshot, history: history, now: now), 4)

        let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: now)!
        XCTAssertNil(HomeWords.todayCount(snapshot, history: history, now: tomorrow), "yesterday's count isn't today's")
    }

    func testASnapshotSavedBeforeTheCountStillLoads() throws {
        let json = #"{"totalContributions":812,"recentLevels":[0,1,2,3,4,0,1],"lastDate":"2026-11-17","fetchedAt":785000000}"#
        let snapshot = try JSONDecoder().decode(ContributionSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.totalContributions, 812)
        XCTAssertNil(snapshot.lastDayCount)
    }

    func testTheSyncLine() {
        let now = Date()
        XCTAssertEqual(HomeWords.synced(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertFalse(HomeWords.synced(now.addingTimeInterval(-240), now: now).isEmpty)
    }
}
