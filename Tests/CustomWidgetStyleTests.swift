import SwiftUI
import XCTest

final class CustomWidgetStyleTests: XCTestCase {
    private func solid(_ hex: UInt32) -> CustomWidgetStyle {
        var style = CustomWidgetStyle.default
        style.usesGradient = false
        style.background = RGBAColor(hex: hex)
        return style
    }

    // MARK: - Saving

    func testADesignSurvivesSaving() throws {
        var style = CustomWidgetStyle.default
        style.squares = RGBAColor(hex: 0x22D3EE)
        style.usesGradient = false
        style.shape = .dot
        style.font = .serif
        style.glows = false

        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
    }

    func testMissingOrUnknownFieldsFallBackWithoutLosingTheRest() throws {
        // A future version's shape, and no background saved at all.
        let json = #"{"squares":{"red":1,"green":0,"blue":0,"opacity":1},"shape":"triangle"}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.squares, RGBAColor(red: 1, green: 0, blue: 0), "the readable choice is kept")
        XCTAssertEqual(decoded.shape, CustomWidgetStyle.default.shape)
        XCTAssertEqual(decoded.background, CustomWidgetStyle.default.background)
    }

    func testColorsSurviveTheColorPickerRoundTrip() {
        let original = RGBAColor(hex: 0xFF7A59)
        let back = RGBAColor(original.color)
        XCTAssertEqual(back.red, original.red, accuracy: 0.001)
        XCTAssertEqual(back.green, original.green, accuracy: 0.001)
        XCTAssertEqual(back.blue, original.blue, accuracy: 0.001)
        XCTAssertEqual(back.opacity, 1, accuracy: 0.001)
    }

    // MARK: - Staying readable

    func testContrastMatchesWCAG() {
        XCTAssertEqual(RGBAColor.white.contrast(with: RGBAColor(red: 0, green: 0, blue: 0)), 21, accuracy: 0.01)
        XCTAssertEqual(RGBAColor.white.contrast(with: .white), 1, accuracy: 0.001)
        // #767676 on white is the textbook just-passes-AA example, 4.54:1.
        XCTAssertEqual(RGBAColor(hex: 0x767676).contrast(with: .white), 4.54, accuracy: 0.02)
    }

    func testTextTurnsDarkOnLightBackdropsAndLightOnDarkOnes() {
        let cream = solid(0xFFF8E7)
        XCTAssertFalse(cream.usesLightText)
        XCTAssertEqual(WidgetStyle.custom.pinnedColorScheme(custom: cream), .light)

        let navy = solid(0x101828)
        XCTAssertTrue(navy.usesLightText)
        XCTAssertEqual(WidgetStyle.custom.pinnedColorScheme(custom: navy), .dark)
    }

    func testSquaresOnlyColorTheNumberWhenTheyRead() {
        var style = solid(0x0B1026)
        style.squares = RGBAColor(hex: 0xFF7A59)
        XCTAssertTrue(style.squaresStandOut)

        style.squares = RGBAColor(hex: 0x1A2040) // navy on navy
        XCTAssertFalse(style.squaresStandOut, "the number would vanish; it should fall back to the text color")
    }

    func testAGradientIsJudgedByItsWeakestEnd() {
        var style = CustomWidgetStyle.default
        style.usesGradient = true
        style.background = RGBAColor(hex: 0xFFFFFF)
        style.backgroundEnd = RGBAColor(hex: 0x000000)
        style.squares = RGBAColor(hex: 0xFFFF66) // bright on black, invisible on white
        XCTAssertFalse(style.squaresStandOut)
    }

    func testTheStartingDesignIsReadable() {
        let style = CustomWidgetStyle.default
        XCTAssertTrue(style.usesLightText)
        XCTAssertTrue(style.squaresStandOut)
    }

    func testAPickedEmptyColorIsUsedAndAnAutomaticOneIsWorkedOut() {
        var style = CustomWidgetStyle.default
        XCTAssertNil(style.emptySquares)
        XCTAssertTrue(style.emptySquaresShow)

        style.emptySquares = RGBAColor(hex: 0x445566)
        XCTAssertEqual(RGBAColor(style.theme.levels[0]), RGBAColor(hex: 0x445566))
    }

    func testAnEmptyColorMatchingTheBackdropIsFlagged() {
        var style = solid(0x0B1026)
        style.emptySquares = RGBAColor(hex: 0x0B1026)
        XCTAssertFalse(style.emptySquaresShow)
    }

    func testSpacingAndMinimalReachTheTheme() {
        var style = CustomWidgetStyle.default
        XCTAssertEqual(style.theme.spacing, 1)
        XCTAssertFalse(style.theme.hidesText)

        style.spacing = .roomy
        style.minimal = true
        XCTAssertGreaterThan(style.theme.spacing, 1)
        XCTAssertTrue(style.theme.hidesText)
        XCTAssertTrue(style.theme.monochrome.hidesText, "a tinted home screen keeps it minimal")
    }

    func testAStyleSavedBeforeTheseOptionsGetsTheirDefaults() throws {
        let json = #"{"squares":{"red":1,"green":0,"blue":0,"opacity":1},"shape":"dot"}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))

        XCTAssertNil(decoded.emptySquares)
        XCTAssertEqual(decoded.spacing, .standard)
        XCTAssertFalse(decoded.minimal)
        XCTAssertEqual(decoded.shape, .dot)
    }

    func testTheNewOptionsSurviveSaving() throws {
        var style = CustomWidgetStyle.default
        style.emptySquares = RGBAColor(hex: 0x222222)
        style.spacing = .tight
        style.minimal = true
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
    }

    func testAMissedDayColorIsOptional() throws {
        var style = CustomWidgetStyle.default
        XCTAssertNil(style.theme.missed)

        style.missedSquares = RGBAColor(hex: 0xE5484D)
        XCTAssertEqual(style.theme.missed.map(RGBAColor.init), RGBAColor(hex: 0xE5484D))
        XCTAssertNil(style.theme.monochrome.missed, "one tint can't color it apart")

        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded.missedSquares, style.missedSquares)
    }

    func testAMissedColorMatchingTheBackdropIsFlagged() {
        var style = solid(0x0B1026)
        XCTAssertTrue(style.missedSquaresShow, "none picked is fine")
        style.missedSquares = RGBAColor(hex: 0x0B1026)
        XCTAssertFalse(style.missedSquaresShow)
        style.missedSquares = RGBAColor(hex: 0xE5484D)
        XCTAssertTrue(style.missedSquaresShow)
    }

    func testEveryChoiceHasAName() {
        for name in CellShapeChoice.allCases.map(\.name) + FontChoice.allCases.map(\.name)
            + WeightChoice.allCases.map(\.name) + SpacingChoice.allCases.map(\.name)
            + DayOffMark.allCases.map(\.name) + TestScenario.allCases.map(\.name) {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testEveryShapeHasAnOutlineToDraw() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        for shape in CellShapeChoice.allCases {
            let path = CellShape(cornerFraction: shape.cornerFraction, form: shape.form).path(in: rect)
            XCTAssertFalse(path.isEmpty, "\(shape)")
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect), "\(shape) stays inside its cell")
        }
    }

    func testShapesAndTypeReachTheTheme() {
        var style = CustomWidgetStyle.default
        style.shape = .heart
        style.font = .condensed
        style.weight = .heavy
        let theme = style.theme

        XCTAssertEqual(theme.form, .heart)
        XCTAssertEqual(theme.fontWidth, .compressed)
        XCTAssertEqual(theme.numberWeight, .heavy)
        XCTAssertEqual(theme.monochrome.form, .heart, "a tinted home screen keeps the shape")
    }

    func testAFreezeStaysApartFromBlueSquares() {
        var blue = solid(0x0B1026)
        blue.squares = RGBAColor(hex: 0x7DD3FC)
        XCTAssertNotEqual(RGBAColor(blue.theme.freeze), RGBAColor(hex: 0x7DD3FC))

        var coral = solid(0x0B1026)
        coral.squares = RGBAColor(hex: 0xFF7A59)
        XCTAssertEqual(RGBAColor(coral.theme.freeze), RGBAColor(hex: 0x7DD3FC), "ice blue everywhere else")
    }

    func testAStyleSavedBeforeWeightWasAChoiceStaysBold() throws {
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(#"{"shape":"star"}"#.utf8))
        XCTAssertEqual(decoded.weight, .bold)
        XCTAssertEqual(decoded.shape, .star)
    }

    func testEveryStarterLookIsReadable() {
        for (index, style) in CustomWidgetStyle.starters.enumerated() {
            XCTAssertTrue(style.squaresStandOut, "starter \(index)")
        }
        XCTAssertEqual(Set(CustomWidgetStyle.starters.map(\.squares.red)).count, CustomWidgetStyle.starters.count, "no two alike")
    }

    func testNotYetIsARingSinceTheSquareColorCouldBeAnything() {
        XCTAssertTrue(CustomWidgetStyle.default.theme.ringsPending)
        // Since 1.3 every look empties its dot to a ring while today is owed.
        XCTAssertTrue(WidgetStyle.ember.theme(for: .dark).ringsPending, "built-in styles ring it too")
    }

    // MARK: - Cell mode

    func testAStyleSavedBeforeCellModesDrawsSquares() throws {
        let json = #"{"squares":{"red":1,"green":0,"blue":0,"opacity":1},"shape":"dot","glows":true}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.cellMode, .squares)
        XCTAssertEqual(decoded.shape, .dot, "the rest of the design is kept")

        let unknown = #"{"cellMode":"sparkles"}"#
        XCTAssertEqual(try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(unknown.utf8)).cellMode, .squares)
    }

    func testMarksSurviveSavingAndReachTheTheme() throws {
        var style = CustomWidgetStyle.default
        style.cellMode = .marks
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)

        let theme = style.theme
        XCTAssertEqual(theme.cellMode, .marks)
        XCTAssertEqual(RGBAColor(theme.markInk).hex, style.squares.hex, "every symbol in the squares color")
        XCTAssertEqual(theme.monochrome.cellMode, .marks, "a tinted home screen keeps the symbols")
        XCTAssertEqual(CustomWidgetStyle.default.theme.cellMode, .squares)
    }

    // MARK: - Starting from a built-in look

    func testSeedingKeepsEachLooksShapeTypeAndGlow() {
        let expected: [WidgetStyle: (CellShapeChoice, FontChoice, Bool, CellMode)] = [
            .classic: (.soft, .standard, false, .squares),
            .aurora: (.rounded, .standard, true, .squares),
            .ember: (.rounded, .standard, true, .squares),
            .terminal: (.square, .monospaced, false, .squares),
            .paper: (.dot, .serif, false, .squares),
            .marks: (.soft, .standard, false, .marks),
        ]
        XCTAssertEqual(Set(expected.keys), Set(WidgetStyle.builtIn), "every built-in look has a starting point")
        for (look, (shape, font, glows, mode)) in expected {
            let seeded = CustomWidgetStyle.seeded(from: look)
            XCTAssertEqual(seeded.shape, shape, "\(look)")
            XCTAssertEqual(seeded.font, font, "\(look)")
            XCTAssertEqual(seeded.glows, glows, "\(look)")
            XCTAssertEqual(seeded.cellMode, mode, "\(look)")
            XCTAssertEqual(seeded.weight, .bold, "\(look)")
            XCTAssertFalse(seeded.minimal)
            XCTAssertNil(seeded.missedSquares)
        }
    }

    func testSeedingTakesEachLooksColors() {
        let classic = CustomWidgetStyle.seeded(from: .classic)
        XCTAssertEqual(classic.background, RGBAColor(hex: 0x0D1117))
        XCTAssertFalse(classic.usesGradient)
        XCTAssertEqual(classic.squares, RGBAColor(hex: 0x39D353))
        XCTAssertEqual(classic.emptySquares, RGBAColor(hex: 0x161B22))

        let paper = CustomWidgetStyle.seeded(from: .paper)
        XCTAssertEqual(paper.background, RGBAColor(hex: 0xF7F2E8))
        XCTAssertEqual(paper.backgroundEnd, RGBAColor(hex: 0xEDE5D6))
        XCTAssertTrue(paper.usesGradient)
        XCTAssertEqual(paper.squares, RGBAColor(hex: 0x24211D))

        let marks = CustomWidgetStyle.seeded(from: .marks)
        XCTAssertEqual(marks.squares, RGBAColor(hex: 0xF2F2F2), "the ink")
        XCTAssertEqual(marks.background, RGBAColor(hex: 0x111113))

        XCTAssertEqual(CustomWidgetStyle.seeded(from: .custom), .default)
    }

    func testEverySeededLookIsReadableAndKeepsItsLightOrDark() {
        for look in WidgetStyle.builtIn {
            let seeded = CustomWidgetStyle.seeded(from: look)
            XCTAssertTrue(seeded.squaresStandOut, "\(look)")
            let expected = look.pinnedColorScheme() ?? .dark
            XCTAssertEqual(WidgetStyle.custom.pinnedColorScheme(custom: seeded), expected, "\(look)")
            // Empty days keep the look's own color, even where that's
            // fainter than the editor's own warning line, as GitHub's is.
            let empty = look.theme(for: expected).levels[0]
            XCTAssertEqual(seeded.emptySquares.map(\.hex), RGBAColor(empty).hex, "\(look)")
        }
    }

    func testASeededLookSurvivesSaving() throws {
        for look in WidgetStyle.builtIn {
            let seeded = CustomWidgetStyle.seeded(from: look)
            XCTAssertEqual(try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(seeded)), seeded, "\(look)")
        }
    }

    func testTheSoftSquareHasAFloorUnderItsCorners() {
        XCTAssertEqual(CellShapeChoice.soft.cornerFraction, 0.18)
        XCTAssertEqual(CellShapeChoice.soft.minimumCorner, 2)
        XCTAssertEqual(CellShape.radius(side: 8, cornerFraction: 0.18, minimumCorner: 2), 2, "small cells keep 2pt")
        XCTAssertEqual(CellShape.radius(side: 40, cornerFraction: 0.18, minimumCorner: 2), 7.2, accuracy: 0.001)
        XCTAssertEqual(CellShape.radius(side: 3, cornerFraction: 0.18, minimumCorner: 2), 1.5, "never past round")
        for shape in CellShapeChoice.allCases where shape != .soft {
            XCTAssertEqual(shape.minimumCorner, 0, "\(shape) is as it was")
        }
    }

    func testChoicesMapToTheirShapeAndType() {
        XCTAssertEqual(CellShapeChoice.square.cornerFraction, 0)
        XCTAssertEqual(CellShapeChoice.dot.cornerFraction, 0.5)
        XCTAssertEqual(FontChoice.monospaced.design, .monospaced)

        var style = CustomWidgetStyle.default
        style.shape = .dot
        style.font = .serif
        let theme = WidgetStyle.custom.theme(for: .dark, custom: style)
        XCTAssertEqual(theme.cornerFraction, 0.5)
        XCTAssertEqual(theme.fontDesign, .serif)
        XCTAssertEqual(theme.levels.count, 5)
    }
}

extension RGBAColor {
    /// Components to the nearest 8 bits, so colors that went through
    /// SwiftUI compare equal to the hex they were made from. Opacity too.
    var hex: UInt64 {
        func byte(_ value: Double) -> UInt64 { UInt64(max(0, min(255, (value * 255).rounded()))) }
        return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(opacity)
    }
}

// MARK: - The number's color

extension CustomWidgetStyleTests {
    func testAStyleSavedBeforeTheNumberColorChoiceKeepsItsSquareColorNumber() throws {
        let json = #"{"background":{"red":0.043,"green":0.063,"blue":0.149,"opacity":1},"usesGradient":false,"squares":{"red":1,"green":0.478,"blue":0.349,"opacity":1}}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))

        XCTAssertFalse(decoded.numberUsesTextColor)
        XCTAssertTrue(decoded.squaresStandOut)
        XCTAssertEqual(RGBAColor(decoded.numberColor).hex, decoded.squares.hex, "drawn exactly as before")
    }

    func testTheNumberColorChoiceSurvivesSaving() throws {
        var style = CustomWidgetStyle.default
        style.numberUsesTextColor = true
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
        XCTAssertEqual(RGBAColor(decoded.numberColor).hex, RGBAColor.white.hex)
    }

    func testEachSeededLookDrawsItsNumberLikeTheBuiltInLook() {
        // Classic, Terminal, Paper and Marks draw the number in the text color.
        // Aurora's and Ember's gradients come closest as the square color.
        let usesText: [WidgetStyle: Bool] = [
            .classic: true, .aurora: false, .ember: false, .terminal: true, .paper: true, .marks: true,
        ]
        XCTAssertEqual(Set(usesText.keys), Set(WidgetStyle.builtIn))
        for (look, text) in usesText {
            let seeded = CustomWidgetStyle.seeded(from: look)
            XCTAssertEqual(seeded.numberUsesTextColor, text, "\(look)")
            let expected = text ? (seeded.usesLightText ? RGBAColor.white : .ink) : seeded.squares
            XCTAssertEqual(RGBAColor(seeded.numberColor).hex, expected.hex, "\(look)")
        }
        XCTAssertNotEqual(
            RGBAColor(CustomWidgetStyle.seeded(from: .classic).numberColor).hex, RGBAColor(hex: 0x39D353).hex,
            "a seeded Classic's number isn't green"
        )
    }

    func testRecoloringASeededLookLeavesItsNumberAlone() {
        var marks = CustomWidgetStyle.seeded(from: .marks)
        marks.squares = RGBAColor(hex: 0xF472B6)
        XCTAssertEqual(RGBAColor(marks.numberColor).hex, RGBAColor.white.hex)

        var aurora = CustomWidgetStyle.seeded(from: .aurora)
        aurora.squares = RGBAColor(hex: 0xF472B6)
        XCTAssertEqual(RGBAColor(aurora.numberColor).hex, aurora.squares.hex)
    }
}
