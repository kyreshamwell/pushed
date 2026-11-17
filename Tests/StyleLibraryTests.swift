import XCTest

final class StyleLibraryTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    private func design(_ hex: UInt32) -> CustomWidgetStyle {
        var style = CustomWidgetStyle.default
        style.squares = RGBAColor(hex: hex)
        return style
    }

    /// Three saved styles: Coral, Mint and Sky, none checked.
    private var three: StyleLibrary {
        var library = StyleLibrary.starting(with: design(0xFF7A59))
        library.styles[0].name = "Coral"
        library.add(design(0x6EE7B7), named: "Mint")
        library.add(design(0x7DD3FC), named: "Sky")
        return library
    }

    // MARK: - Carrying over the old custom style

    func testTheOldCustomStyleBecomesTheFirstSavedOne() {
        let earlier = design(0x22D3EE)
        let library = StyleLibrary.starting(with: earlier)

        XCTAssertEqual(library.styles.count, 1)
        XCTAssertEqual(library.styles[0].style, earlier)
        XCTAssertEqual(library.styles[0].name, "My Style")
    }

    func testTheCarriedOverStyleHasTheSameIDEverywhere() {
        // The app and the widget each build it before either has saved it.
        XCTAssertEqual(StyleLibrary.starting().styles[0].id, StyleLibrary.starting().styles[0].id)
        XCTAssertEqual(StyleLibrary.starting().styles[0].id, StyleLibrary.firstStyleID)
    }

    func testAWidgetSetToCustomBeforeThereWasAChoiceWearsTheFirstStyle() {
        let look = three.look(for: .custom, saved: nil)
        XCTAssertEqual(look.style, .custom)
        XCTAssertEqual(look.name, "Coral")
    }

    // MARK: - Picking a saved style

    func testAWidgetWearsTheStylePickedForIt() {
        let library = three
        let mint = library.styles[1]
        XCTAssertEqual(library.look(for: .custom, saved: mint.id).custom, mint.style)
    }

    func testADeletedStyleFallsBackToTheFirst() {
        var library = three
        let sky = library.styles[2]
        library[sky.id] = nil

        XCTAssertEqual(library.styles.count, 2)
        XCTAssertEqual(library.look(for: .custom, saved: sky.id).name, "Coral")
    }

    func testTheLastStyleCannotBeDeleted() {
        var library = StyleLibrary.starting()
        library[StyleLibrary.firstStyleID] = nil

        XCTAssertEqual(library.styles.count, 1)
        XCTAssertFalse(library.canRemove)
    }

    func testBuiltInStylesIgnoreTheLibrary() {
        let look = three.look(for: .terminal, saved: three.styles[1].id)
        XCTAssertEqual(look.style, .terminal)
        XCTAssertEqual(look.name, "Terminal")
    }

    // MARK: - Adding and copying

    func testNewStylesGetNamesThatArentTaken() {
        var library = StyleLibrary.starting()
        let second = library.add()
        let third = library.add(named: "Style 2")

        XCTAssertEqual(second?.name, "Style 2")
        XCTAssertEqual(third?.name, "Style 2 2")
    }

    func testEachNewStyleStartsFromADifferentLook() {
        var library = StyleLibrary.starting()
        let second = library.add()
        let third = library.add()

        XCTAssertNotEqual(second?.style, library.styles[0].style)
        XCTAssertNotEqual(second?.style, third?.style)
    }

    func testACopySitsBesideTheOriginal() {
        var library = three
        let copy = library.duplicate(library.styles[0].id)

        XCTAssertEqual(library.styles.map(\.displayName), ["Coral", "Coral copy", "Mint", "Sky"])
        XCTAssertEqual(copy?.style, library.styles[0].style)
        XCTAssertNotEqual(copy?.id, library.styles[0].id)
    }

    func testTheLibraryStopsGrowingWhenFull() {
        var library = StyleLibrary.starting()
        while library.canAdd { library.add() }

        XCTAssertEqual(library.styles.count, StyleLibrary.maxStyles)
        XCTAssertNil(library.add())
        XCTAssertNil(library.duplicate(library.styles[0].id))
    }

    func testAClearedNameStillShowsAsSomething() {
        XCTAssertEqual(SavedStyle(name: "   ").displayName, "Untitled")
    }

    // MARK: - Daily rotation

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// The names the rotation shows on each day from `first`, for `count` days.
    private func names(_ library: StyleLibrary, from first: String, days count: Int) -> [String] {
        let start = date(first)
        return (0..<count).map {
            library.rotationPick(on: calendar.date(byAdding: .day, value: $0, to: start)!).name
        }
    }

    func testNothingInTheRotationShowsClassic() {
        XCTAssertTrue(three.rotation.isEmpty)
        XCTAssertEqual(three.rotationPick(on: date("2026-10-12")).style, .classic)
        XCTAssertEqual(three.look(for: .rotation, on: date("2026-10-12")).style, .classic)
        XCTAssertTrue(three.rotationSchedule(from: date("2026-10-12")).isEmpty)
    }

    func testLooksTakeTurnsInTheOrderTheyWereAdded() {
        var library = three
        let day = date("2026-10-12")
        library.addToRotation(.builtIn(.paper), on: day)
        library.addToRotation(.saved(library.styles[2].id), on: day)
        library.addToRotation(.builtIn(.aurora), on: day)

        XCTAssertEqual(library.rotation, [.builtIn(.paper), .saved(library.styles[2].id), .builtIn(.aurora)])
        XCTAssertEqual(names(library, from: "2026-10-12", days: 6), ["Paper", "Sky", "Aurora", "Paper", "Sky", "Aurora"])
        XCTAssertEqual(library.rotationSchedule(from: day).compactMap { library.look(of: $0)?.name }, ["Paper", "Sky", "Aurora"])
    }

    func testAddingALookNeverChangesTodaysLook() {
        var library = three
        let monday = date("2026-10-12")
        library.addToRotation(.builtIn(.ember), on: monday)
        library.addToRotation(.builtIn(.terminal), on: monday)
        let wednesday = date("2026-10-14")
        let before = library.rotationPick(on: wednesday).name

        library.addToRotation(.builtIn(.marks), on: wednesday)
        XCTAssertEqual(library.rotationPick(on: wednesday).name, before)
        XCTAssertEqual(names(library, from: "2026-10-14", days: 3), ["Ember", "Terminal", "Marks"])
    }

    func testTheFirstLookAddedIsTodays() {
        var library = three
        let day = date("2026-10-20")
        library.addToRotation(.builtIn(.terminal), on: day)
        XCTAssertEqual(library.rotationPick(on: day).name, "Terminal")
    }

    func testRemovingTodaysLookMovesTodayToTheNextOne() {
        var library = three
        let day = date("2026-10-12")
        for style in [WidgetStyle.classic, .aurora, .ember] { library.addToRotation(.builtIn(style), on: day) }
        XCTAssertEqual(library.rotationPick(on: day).name, "Classic")

        library.removeFromRotation(.builtIn(.classic), on: day)
        XCTAssertEqual(names(library, from: "2026-10-12", days: 3), ["Aurora", "Ember", "Aurora"])
    }

    func testRemovingTheLastLookInLineWrapsTodayToTheFirst() {
        var library = three
        let monday = date("2026-10-12")
        for style in [WidgetStyle.classic, .aurora, .ember] { library.addToRotation(.builtIn(style), on: monday) }
        let wednesday = date("2026-10-14")
        XCTAssertEqual(library.rotationPick(on: wednesday).name, "Ember")

        library.removeFromRotation(.builtIn(.ember), on: wednesday)
        XCTAssertEqual(names(library, from: "2026-10-14", days: 2), ["Classic", "Aurora"])
    }

    func testRemovingAnotherLookKeepsTodaysLook() {
        var library = three
        let monday = date("2026-10-12")
        for style in [WidgetStyle.classic, .aurora, .ember, .paper] { library.addToRotation(.builtIn(style), on: monday) }
        let wednesday = date("2026-10-14")
        XCTAssertEqual(library.rotationPick(on: wednesday).name, "Ember")

        library.removeFromRotation(.builtIn(.classic), on: wednesday)
        XCTAssertEqual(names(library, from: "2026-10-14", days: 3), ["Ember", "Paper", "Aurora"])

        library.removeFromRotation(.builtIn(.paper), on: wednesday)
        XCTAssertEqual(names(library, from: "2026-10-14", days: 3), ["Ember", "Aurora", "Ember"])
    }

    func testRemovingEveryLookEmptiesTheRotation() {
        var library = three
        let day = date("2026-10-12")
        library.toggleRotation(.builtIn(.aurora), on: day)
        library.toggleRotation(.builtIn(.aurora), on: day)
        XCTAssertTrue(library.rotation.isEmpty)
        XCTAssertNil(library.anchor)
        XCTAssertEqual(library.rotationPick(on: day).style, .classic)
    }

    func testTheRotationHoldsAllDay() {
        var library = three
        let day = date("2026-10-12")
        library.addToRotation(.builtIn(.aurora), on: day)
        library.addToRotation(.builtIn(.ember), on: day)
        let morning = day.addingTimeInterval(60)
        let night = day.addingTimeInterval(24 * 3600 - 60)
        XCTAssertEqual(library.rotationPick(on: morning), library.rotationPick(on: night))
    }

    func testOneLookStaysPut() {
        var library = three
        library.toggleRotation(library.styles[1].id, on: date("2026-10-12"))
        XCTAssertEqual(Set(names(library, from: "2026-10-12", days: 7)), ["Mint"])
    }

    func testOnlyRealLooksCanBeAdded() {
        var library = three
        library.addToRotation(.builtIn(.custom))
        library.addToRotation(.builtIn(.rotation))
        library.addToRotation(.saved(UUID()))
        library.addToRotation(.builtIn(.aurora))
        library.addToRotation(.builtIn(.aurora))
        XCTAssertEqual(library.rotation, [.builtIn(.aurora)])
    }

    func testDeletingASavedStyleTakesItOutOfTheRotation() {
        var library = three
        let day = date("2026-10-12")
        let mint = library.styles[1]
        library.addToRotation(.saved(mint.id), on: day)
        library.addToRotation(.builtIn(.ember), on: day)
        XCTAssertEqual(library.rotationPick(on: day).name, "Mint")

        library.remove(mint.id, on: day)
        XCTAssertNil(library[mint.id])
        XCTAssertEqual(library.rotation, [.builtIn(.ember)])
        XCTAssertEqual(library.rotationPick(on: day).name, "Ember", "today moves on to the next look")

        library.addToRotation(.saved(library.styles[1].id), on: day)
        library[library.styles[1].id] = nil
        XCTAssertEqual(library.rotation, [.builtIn(.ember)], "the subscript deletes from the rotation too")
    }

    func testAWidgetSetToRotationWearsWhatTheStripShowsOnAnyDay() {
        var library = three
        let today = date("2026-10-12")
        library.addToRotation(.builtIn(.aurora), on: today)
        library.addToRotation(.builtIn(.ember), on: today)
        library.addToRotation(.saved(library.styles[0].id), on: today)
        let strip = library.rotationSchedule(from: today)

        for offset in 0..<40 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let expected = library.look(of: strip[offset % strip.count])
            XCTAssertEqual(library.look(for: .rotation, on: day), expected, "day \(offset)")
            // The widget's midnight entry is drawn for the first moment of the day.
            XCTAssertEqual(library.look(for: .rotation, on: calendar.startOfDay(for: day)), expected)
        }
        XCTAssertNotEqual(library.look(for: .rotation, on: today).style, .rotation, "always something drawable")
    }

    func testTheScheduleStartsWithTodaysLook() {
        var library = three
        let monday = date("2026-10-12")
        for style in [WidgetStyle.classic, .aurora, .ember] { library.addToRotation(.builtIn(style), on: monday) }
        XCTAssertEqual(
            library.rotationSchedule(from: date("2026-10-13")),
            [.builtIn(.aurora), .builtIn(.ember), .builtIn(.classic)]
        )
    }

    // MARK: - The rotation from 1.2

    /// A 1.2 library as it was saved: a flag on each style, plus the built-ins.
    private func legacy(checked: [Int], builtIns: [String]) throws -> StyleLibrary {
        let styles = try three.styles.enumerated().map { index, saved -> [String: Any] in
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
            object["inRotation"] = checked.contains(index)
            return object
        }
        let json: [String: Any] = ["styles": styles, "rotatingBuiltIns": builtIns]
        return try JSONDecoder().decode(StyleLibrary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// What 1.2 showed on a day: its pool, counted from 1 January 2001.
    private func oldPick(_ pool: [String], on day: Date) -> String {
        let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1))!
        let number = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: day)).day!
        return pool[number % pool.count]
    }

    func testTheOldRotationKeepsItsOrderYoursFirst() throws {
        let library = try legacy(checked: [2, 0], builtIns: ["paper", "terminal"])
        XCTAssertEqual(library.rotationLooks.map(\.name), ["Coral", "Sky", "Terminal", "Paper"])
    }

    func testEveryWidgetKeepsItsLookAfterTheUpdate() throws {
        let library = try legacy(checked: [1], builtIns: ["ember", "aurora"])
        let pool = ["Mint", "Aurora", "Ember"]
        for offset in 0..<30 {
            let day = calendar.date(byAdding: .day, value: offset, to: date("2026-11-17"))!
            XCTAssertEqual(library.look(for: .rotation, on: day).name, oldPick(pool, on: day))
        }
    }

    func testWithNothingCheckedTheOldRotationWasAllOfYourStyles() throws {
        let library = try legacy(checked: [], builtIns: [])
        XCTAssertEqual(library.rotationLooks.map(\.name), ["Coral", "Mint", "Sky"])
        let day = date("2026-11-17")
        XCTAssertEqual(library.rotationPick(on: day).name, oldPick(["Coral", "Mint", "Sky"], on: day))
    }

    func testAnOldLibraryChangesSmoothlyAfterTheUpdate() throws {
        var library = try legacy(checked: [], builtIns: ["aurora"])
        let day = date("2026-11-17")
        let today = library.rotationPick(on: day).name
        library.addToRotation(.builtIn(.marks), on: day)
        XCTAssertEqual(library.rotationPick(on: day).name, today)
    }

    func testAnUnknownLookIsSkipped() throws {
        let json = #"{"styles":[],"rotation":["aurora","sparkles","ember"],"anchor":{"day":9000,"index":1}}"#
        let library = try JSONDecoder().decode(StyleLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(library.rotation, [.builtIn(.aurora), .builtIn(.ember)])
    }

    func testAStartingLibraryCanCarryTheOldFallback() {
        XCTAssertTrue(StyleLibrary.starting().rotation.isEmpty)
        let upgraded = StyleLibrary.starting(rotating: true)
        XCTAssertEqual(upgraded.rotation, [.saved(StyleLibrary.firstStyleID)])
        XCTAssertEqual(upgraded.rotationPick(on: date("2026-11-17")).name, "My Style")
    }

    // MARK: - Saved data

    func testTheLibrarySurvivesSaving() throws {
        var library = three
        library.addToRotation(.saved(library.styles[1].id))
        library.addToRotation(.builtIn(.ember))

        let decoded = try JSONDecoder().decode(StyleLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
    }

    func testASavedStyleMissingFieldsKeepsItsDesign() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","style":{"squares":{"red":1,"green":0,"blue":0,"opacity":1}}}"#
        let decoded = try JSONDecoder().decode(SavedStyle.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, StyleLibrary.firstStyleID)
        XCTAssertEqual(decoded.style.squares, RGBAColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(decoded.displayName, "Untitled")
    }
}
