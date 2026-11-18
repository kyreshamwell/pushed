import SwiftUI
import WidgetKit
import XCTest

/// Not a test of behavior: draws the widget in every style to PNG files so a
/// change to how squares look can be checked by eye without a home screen,
/// and against the numbers in Design/1.3-redesign/Widget.dc.html.
/// Skipped unless a folder is given:
///
///     TEST_RUNNER_PUSHED_RENDER_DIR=/tmp/pushed-renders xcodebuild test \
///         -only-testing:PushedTests/RenderPreviews ...
@MainActor
final class RenderPreviews: XCTestCase {
    private var outputFolder: URL? {
        ProcessInfo.processInfo.environment["PUSHED_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func write(_ view: some View, named name: String, to folder: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "\(name) didn't render")
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// The sample year with its weekends emptied out, so with Saturday and
    /// Sunday as rest days there's a mix of days off, pushes and real gaps.
    private func weekendsOff(_ sample: ContributionSnapshot, asOf now: Date) -> ContributionSnapshot {
        let cal = Calendar(identifier: .gregorian)
        let last = sample.recentLevels.count - 1
        let levels = sample.recentLevels.enumerated().map { index, level -> Int in
            let day = cal.date(byAdding: .day, value: index - last, to: now)!
            let weekday = cal.component(.weekday, from: day)
            return weekday == 1 || weekday == 7 ? 0 : level
        }
        return ContributionSnapshot(
            totalContributions: sample.totalContributions,
            recentLevels: levels,
            lastDate: sample.lastDate,
            fetchedAt: sample.fetchedAt
        )
    }

    func testRenderEveryStyle() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Saturday, so today itself is a rest day in the second set.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-17")!
        let sample = ContributionSnapshot.sample(asOf: now)
        let resting = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-07": .freeze]
        )
        let sets: [(String, ContributionSnapshot, StreakProtection)] = [
            ("plain", sample, .none),
            ("rest", weekendsOff(sample, asOf: now), resting),
        ]
        let families: [(WidgetFamily, String)] = [(.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")]

        for (setName, snapshot, protection) in sets {
            for (family, familyName) in [(WidgetFamily.accessoryCircular, "circular"), (.accessoryRectangular, "rectangular"), (.accessoryInline, "inline")] {
                let size: CGSize = family == .accessoryCircular ? CGSize(width: 72, height: 72)
                    : family == .accessoryRectangular ? CGSize(width: 172, height: 76) : CGSize(width: 234, height: 26)
                let lock = LockScreenView(snapshot: snapshot, family: family, protection: protection, now: now, icon: "🔥")
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .padding(16)
                    .background(Color(hex: 0x1B2A44))
                try write(lock, named: "\(setName)-lock-\(familyName)", to: folder)
            }
            // Classic follows the phone's appearance, so it's drawn both ways.
            let looks: [(WidgetStyle, String, ColorScheme)] = WidgetStyle.designs.map { ($0, $0.rawValue, .dark) }
                + [(.classic, "classic-light", .light)]
            for (style, lookName, scheme) in looks {
                for layout in WidgetLayout.allCases {
                    for (family, familyName) in families {
                        let card = WidgetPreviewCard(
                            snapshot: snapshot,
                            family: family,
                            style: style,
                            layout: layout,
                            icon: "🔥",
                            custom: .default,
                            protection: protection,
                            now: now
                        )
                        .padding(24)
                        .background(Color(hex: scheme == .dark ? 0x101014 : 0xE5E5EA))
                        .environment(\.colorScheme, scheme)
                        try write(card, named: "\(setName)-\(lookName)-\(layout.rawValue)-\(familyName)", to: folder)
                    }
                }
            }
        }
    }

    /// The per-widget options and the extra style controls, side by side.
    func testRenderCustomizationOptions() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Wednesday, so the week layout has days done and days to come.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let snapshot = weekendsOff(.sample(asOf: now), asOf: now)
        let protection = StreakProtection(schedules: [.init(from: "2026-06-01", weekdays: [1, 7])])

        func card(
            _ name: String, family: WidgetFamily = .systemMedium, style: WidgetStyle = .classic,
            layout: WidgetLayout = .graph, stat: WidgetStat = .streak,
            custom: CustomWidgetStyle = .default, snapshot: ContributionSnapshot? = nil
        ) throws {
            let view = WidgetPreviewCard(
                snapshot: snapshot ?? defaultSnapshot, family: family, style: style, layout: layout,
                stat: stat, icon: "🔥", custom: custom, protection: protection, now: now
            )
            .padding(24)
            .background(Color(hex: 0x101014))
            .environment(\.colorScheme, .dark)
            try write(view, named: name, to: folder)
        }
        let defaultSnapshot = snapshot

        for stat in WidgetStat.allCases {
            for (family, size) in [(WidgetFamily.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")] {
                try card("show-graph-\(stat.rawValue)-\(size)", family: family, style: .aurora, stat: stat)
            }
            try card("show-streak-\(stat.rawValue)", style: .aurora, layout: .streak, stat: stat)
        }

        // Not pushed yet: the dot or circle empties and nothing else moves.
        let waiting = weekendsOff(.sample(quiet: 1, asOf: now), asOf: now)
        for style in WidgetStyle.builtIn {
            for (family, size) in [(WidgetFamily.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")] {
                try card("pending-\(style.rawValue)-\(size)", family: family, style: style, snapshot: waiting)
            }
        }

        for style in [WidgetStyle.classic, .terminal, .ember] {
            try card("week-small-\(style.rawValue)", family: .systemSmall, style: style, layout: .week)
            try card("week-medium-\(style.rawValue)", style: style, layout: .week)
            try card("week-large-\(style.rawValue)", family: .systemLarge, style: style, layout: .week)
        }

        var picked = CustomWidgetStyle.starters[1]
        picked.emptySquares = RGBAColor(hex: 0x1F4D47)
        try card("custom-empty-color", style: .custom, custom: picked)
        var roomy = CustomWidgetStyle.default
        roomy.spacing = .roomy
        try card("custom-roomy", style: .custom, custom: roomy)
        var tight = CustomWidgetStyle.default
        tight.spacing = .tight
        try card("custom-tight", style: .custom, custom: tight)
        var minimal = CustomWidgetStyle.starters[4]
        minimal.minimal = true
        try card("custom-minimal-graph", style: .custom, custom: minimal)
        try card("custom-minimal-streak", style: .custom, layout: .streak, custom: minimal)
        try card("custom-minimal-week", family: .systemSmall, style: .custom, layout: .week, custom: minimal)
        try card("custom-minimal-large", family: .systemLarge, style: .custom, custom: minimal)
    }

    /// A freeze and rest days in each way of marking them, and the extra
    /// shapes and type for custom styles.
    func testRenderMarksShapesAndType() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Wednesday the 21st. Sunday is a rest day, Tuesday the 20th frozen.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let rested = weekendsOff(.sample(asOf: now), asOf: now)
        var levels = rested.recentLevels
        levels[levels.count - 2] = 0
        let snapshot = ContributionSnapshot(
            totalContributions: rested.totalContributions, recentLevels: levels,
            lastDate: rested.lastDate, fetchedAt: rested.fetchedAt
        )
        let protection = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-20": .freeze]
        )

        func card(
            _ name: String, family: WidgetFamily = .systemMedium, style: WidgetStyle = .classic,
            layout: WidgetLayout = .graph, custom: CustomWidgetStyle = .default,
            mark: DayOffMark = .ring
        ) throws {
            let view = WidgetPreviewCard(
                snapshot: snapshot, family: family, style: style, layout: layout,
                icon: "🔥", custom: custom, protection: protection, dayOffMark: mark, now: now
            )
            .padding(24)
            .background(Color(hex: 0x101014))
            .environment(\.colorScheme, .dark)
            try write(view, named: name, to: folder)
        }

        // Marks: a symbol for every day, rest days and the freeze included.
        for (family, size) in [(WidgetFamily.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")] {
            for layout in WidgetLayout.allCases {
                try card("marks-\(layout.rawValue)-\(size)", family: family, style: .marks, layout: layout)
            }
        }
        var inked = CustomWidgetStyle.seeded(from: .marks)
        inked.squares = RGBAColor(hex: 0x5B8DEF)
        try card("marks-custom-blue", style: .custom, custom: inked)
        inked.missedSquares = RGBAColor(hex: 0xE5484D)
        try card("marks-custom-missed", family: .systemLarge, style: .custom, custom: inked)

        for mark in DayOffMark.allCases {
            for style in [WidgetStyle.classic, .terminal, .aurora, .paper] {
                try card("mark-\(mark.rawValue)-\(style.rawValue)-week", style: style, layout: .week, mark: mark)
                try card("mark-\(mark.rawValue)-\(style.rawValue)-graph", style: style, mark: mark)
            }
        }

        for shape in CellShapeChoice.allCases {
            var custom = CustomWidgetStyle.starters[shape == .heart ? 4 : 2]
            custom.shape = shape
            try card("shape-\(shape.rawValue)-graph", style: .custom, custom: custom)
            try card("shape-\(shape.rawValue)-week", family: .systemSmall, style: .custom, layout: .week, custom: custom)
        }

        for font in FontChoice.allCases {
            for weight in [WeightChoice.light, .heavy] {
                var custom = CustomWidgetStyle.default
                custom.font = font
                custom.weight = weight
                try card("type-\(font.rawValue)-\(weight.rawValue)", family: .systemSmall, style: .custom, layout: .streak, custom: custom)
            }
        }
    }

    /// Missed days in red next to the rest of a custom style.
    func testRenderMissedDays() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let snapshot = weekendsOff(.sample(asOf: now), asOf: now)
        // Watching since the start of August: earlier gaps stay plain.
        let protection = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-20": .freeze],
            trackedSince: "2026-08-01"
        )
        for (index, base) in [CustomWidgetStyle.default, CustomWidgetStyle.starters[3]].enumerated() {
            var custom = base
            custom.missedSquares = RGBAColor(hex: custom.usesLightText ? 0xE5484D : 0xD93D42)
            for (family, name, layout) in [(WidgetFamily.systemMedium, "graph", WidgetLayout.graph), (.systemLarge, "large", .graph), (.systemMedium, "week", .week)] {
                let view = WidgetPreviewCard(
                    snapshot: snapshot, family: family, style: .custom, layout: layout,
                    icon: "🔥", custom: custom, protection: protection, now: now
                )
                .padding(24)
                .background(Color(hex: 0x101014))
                try write(view, named: "missed-\(index)-\(name)", to: folder)
            }
        }
    }

    /// The widgets for the App Store screenshots: each card on its own with
    /// a clear background, drawn large so it stays sharp once composed. The
    /// streak runs over weekend rest days and one freeze, so the day off
    /// marks and the Marks symbols show. Every built-in look, Marks
    /// included, is drawn in all three sizes and layouts, plus Classic in
    /// light mode and Marks in a picked color. `Scripts/compose_screenshots.py`
    /// lays these out.
    func testRenderStoreWidgets() throws {
        guard let base = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        let folder = base.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Wednesday: this week has days done and days still to come.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        // The run starts after a missed Friday, Oct 2. Its weekdays, less
        // the frozen Tuesday, make a 12 day streak, the same number the demo
        // build shows in the app captures.
        let rested = weekendsOff(.sample(streak: 19, asOf: now), asOf: now)
        var levels = rested.recentLevels
        levels[levels.count - 2] = 0 // Tuesday, covered by the freeze
        let snapshot = ContributionSnapshot(
            totalContributions: rested.totalContributions, recentLevels: levels,
            lastDate: rested.lastDate, fetchedAt: now
        )
        let protection = StreakProtection(
            schedules: [.init(from: "2026-01-01", weekdays: [1, 7])],
            claims: ["2026-10-20": .freeze],
            trackedSince: "2026-08-01"
        )

        func card(
            _ name: String, _ family: WidgetFamily, _ style: WidgetStyle, _ layout: WidgetLayout,
            stat: WidgetStat = .streak, custom: CustomWidgetStyle = .default, scheme: ColorScheme = .dark
        ) throws {
            let view = WidgetPreviewCard(
                snapshot: snapshot, family: family, style: style, layout: layout,
                stat: stat, icon: "🔥", custom: custom, protection: protection, dayOffMark: .stripes, now: now
            )
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 4
            let image = try XCTUnwrap(renderer.uiImage, "\(name) didn't render")
            try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
        }

        let sizes: [(WidgetFamily, String)] = [(.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")]

        // Every built-in look, Marks included, in every layout and size.
        for style in WidgetStyle.builtIn {
            for layout in WidgetLayout.allCases {
                for (family, size) in sizes {
                    try card("\(style.rawValue)-\(layout.rawValue)-\(size)", family, style, layout)
                }
            }
        }

        // Classic follows the phone's appearance, so it's drawn light too.
        // Marks follows whatever color is picked in Customize.
        var blueMarks = CustomWidgetStyle.seeded(from: .marks)
        blueMarks.squares = RGBAColor(hex: 0x5B8DEF)
        for layout in WidgetLayout.allCases {
            for (family, size) in sizes {
                try card("classic-light-\(layout.rawValue)-\(size)", family, .classic, layout, scheme: .light)
                try card("marks-blue-\(layout.rawValue)-\(size)", family, .custom, layout, custom: blueMarks)
            }
        }

        // What Show puts in the header.
        for stat in WidgetStat.allCases {
            try card("aurora-graph-medium-\(stat.rawValue)", .systemMedium, .aurora, .graph, stat: stat)
        }

        // Custom styles, one per shape.
        var lime = CustomWidgetStyle.default
        lime.background = RGBAColor(hex: 0x141414)
        lime.usesGradient = false
        lime.squares = RGBAColor(hex: 0xA3E635)
        lime.font = .condensed
        lime.weight = .heavy
        lime.glows = true
        let looks: [(String, CustomWidgetStyle, CellShapeChoice)] = [
            ("heart", CustomWidgetStyle.starters[4], .heart),
            ("hexagon", CustomWidgetStyle.starters[1], .hexagon),
            ("star", CustomWidgetStyle.starters[2], .star),
            ("diamond", CustomWidgetStyle.starters[0], .diamond),
            ("dot", CustomWidgetStyle.starters[3], .dot),
            ("square", lime, .square),
        ]
        for (name, base, shape) in looks {
            var custom = base
            custom.shape = shape
            custom.missedSquares = RGBAColor(hex: custom.usesLightText ? 0xE5484D : 0xD93D42)
            for layout in WidgetLayout.allCases {
                for (family, size) in [(WidgetFamily.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")] {
                    try card("custom-\(name)-\(layout.rawValue)-\(size)", family, .custom, layout, custom: custom)
                }
            }
        }

        // The Lock Screen, white on clear the way iOS tints it.
        for (family, size, name) in [
            (WidgetFamily.accessoryCircular, CGSize(width: 76, height: 76), "circular"),
            (.accessoryRectangular, CGSize(width: 172, height: 76), "rectangular"),
            (.accessoryInline, CGSize(width: 260, height: 24), "inline"),
        ] {
            let view = LockScreenView(snapshot: snapshot, family: family, protection: protection, now: now, icon: "🔥", dayOffMark: .stripes)
                .frame(width: size.width, height: size.height)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 4
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("lock-\(name).png"))
        }
    }
}
