import SwiftUI
import WidgetKit

/// Everything the home-screen widget draws. It lives in Shared rather than the
/// extension so the app's previews render the exact same view.
///
/// Every layout follows the 1.3 design: 16pt margins, a slim header with the
/// number and today's status, and squares that fill the rest of the frame
/// with a thin ring around today. Every look shares the same layout, so
/// switching looks changes colors, shapes and type and never moves anything.
struct PushedWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    var style: WidgetStyle = .classic
    var layout: WidgetLayout = .graph
    /// The number the widget leads with.
    var stat: WidgetStat = .streak
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    var dayOffMark: DayOffMark = AppConfig.dayOffMark
    /// The moment this is drawn for. A widget entry is laid out ahead of the
    /// time it goes on screen, so the entry's own date is passed in and the
    /// clock is never read here.
    var now = Date()
    /// The system's standard widget margins (16pt on iPhone). The widget
    /// turns the automatic ones off and applies these itself.
    var margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    private var scheme: ColorScheme { style.pinnedColorScheme(custom: custom) ?? colorScheme }

    var body: some View {
        let theme = style.theme(for: scheme, renderingMode: renderingMode, custom: custom)
        content(theme)
            .padding(margins)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fontDesign(theme.fontDesign)
            .fontWidth(theme.fontWidth)
            .environment(\.dayOffMark, dayOffMark)
            .environment(\.colorScheme, scheme)
            .environment(\.customWidgetStyle, custom)
    }

    @ViewBuilder
    private func content(_ theme: WidgetTheme) -> some View {
        if let snapshot {
            let history = snapshot.history(protection: protection, asOf: now)
            let reading = Reading(
                history: history,
                headline: WidgetHeadline(history: history, total: snapshot.totalContributions, stat: stat),
                theme: theme
            )
            GeometryReader { geo in
                layoutView(reading, size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        } else {
            Text("Open Pushed and add your GitHub username + token.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func layoutView(_ reading: Reading, size: CGSize) -> some View {
        switch (layout, family) {
        case (.graph, _): graph(reading, size: size)
        case (.streak, .systemSmall): streakSmall(reading, size: size)
        case (.streak, .systemLarge): streakLarge(reading, size: size)
        case (.streak, _): streakMedium(reading, size: size)
        case (.week, .systemSmall): weekSmall(reading, size: size)
        case (.week, .systemLarge): weekLarge(reading, size: size)
        case (.week, _): weekMedium(reading, size: size)
        }
    }

    /// Everything a layout draws from, worked out once.
    private struct Reading {
        let history: StreakHistory
        let headline: WidgetHeadline
        let theme: WidgetTheme

        var showsWords: Bool { !theme.hidesText }
        var gap: CGFloat { GridFit.gap * theme.spacing }
    }

    // MARK: - Graph layout

    /// The header, then the squares filling everything under it: one row of
    /// weeks on Small and Medium, two on Large with their labels.
    private func graph(_ reading: Reading, size: CGSize) -> some View {
        let plan = GraphLayout(family: family, size: size, labels: reading.showsWords, gap: reading.gap)
        let bands = reading.history.bands(plan.bands, weeks: plan.fit.columns)
        return VStack(alignment: .leading, spacing: plan.headerGap) {
            Group {
                switch family {
                case .systemSmall: smallHeader(reading)
                case .systemLarge: largeHeader(reading, numberSize: 56)
                default: mediumHeader(reading)
                }
            }
            .frame(height: plan.header, alignment: .top)

            VStack(alignment: .leading, spacing: plan.bandGap) {
                ForEach(bands.indices, id: \.self) { index in
                    GraphBandView(band: bands[index], fit: plan.fit, labels: plan.labels, theme: reading.theme)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(graphDescription(bands, history: reading.history))
        }
    }

    // MARK: - Big streak layout

    /// The number big, with the last seven days under it.
    private func streakSmall(_ reading: Reading, size: CGSize) -> some View {
        let strip = RowFit(width: size.width, count: 7, gap: reading.gap)
        let days = reading.history.days(last: 7)
        return VStack(alignment: .leading, spacing: 0) {
            topRow(reading)
            Spacer(minLength: 0)
            bigNumber(reading, size: 46, labelSize: 12)
            Spacer(minLength: 8)
            DayGrid(
                cells: days.indices.map { DayGrid.Cell(content: .day(days[$0]), frame: strip.frame($0)) },
                size: strip.size,
                theme: reading.theme,
                today: days.count - 1
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    /// The number on the left, and as many weeks as fit beside it.
    private func streakMedium(_ reading: Reading, size: CGSize) -> some View {
        let side: CGFloat = 112
        let fit = GridFit(width: size.width - side - 16, height: size.height, gap: reading.gap)
        let band = reading.history.bands(1, weeks: fit.columns)[0]
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                bigNumber(reading, size: 56, labelSize: 13)
                Spacer(minLength: 0)
                TodayStatus(today: reading.history.today, text: reading.headline.status, theme: reading.theme, showsText: reading.showsWords)
            }
            .frame(width: side, height: size.height, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(reading))

            Spacer(minLength: 0)
            GraphBandView(band: band, fit: fit, theme: reading.theme)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(graphDescription([band], history: reading.history))
        }
    }

    /// Large's header with the number bigger still, over one row of weeks.
    private func streakLarge(_ reading: Reading, size: CGSize) -> some View {
        let header: CGFloat = 104
        let labels = reading.showsWords
        let fit = GridFit(
            width: size.width - (labels ? GraphLayout.dayColumn + GraphLayout.dayGap : 0),
            height: size.height - header - GraphLayout.largeHeaderGap - (labels ? GraphLayout.monthRow + GraphLayout.monthGap : 0),
            gap: reading.gap
        )
        let band = reading.history.bands(1, weeks: fit.columns)[0]
        return VStack(alignment: .leading, spacing: GraphLayout.largeHeaderGap) {
            largeHeader(reading, numberSize: 88)
                .frame(height: header, alignment: .top)
            GraphBandView(band: band, fit: fit, labels: labels, theme: reading.theme)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(graphDescription([band], history: reading.history))
        }
    }

    // MARK: - This week layout

    private func weekSmall(_ reading: Reading, size: CGSize) -> some View {
        let row = RowFit(width: size.width, count: 7, gap: reading.gap)
        return VStack(alignment: .leading, spacing: 0) {
            topRow(reading)
            Spacer(minLength: 0)
            bigNumber(reading, size: 42, labelSize: 12)
            Spacer(minLength: 8)
            WeekSquares(week: reading.history.thisWeek, fit: row, theme: reading.theme, letters: reading.showsWords)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    private func weekMedium(_ reading: Reading, size: CGSize) -> some View {
        let letters = reading.showsWords ? WeekSquares.letterSpace : 0
        let room = size.height - GraphLayout.compactHeader - GraphLayout.compactHeaderGap - letters
        let row = RowFit(width: size.width, count: 7, gap: 8 * reading.theme.spacing, maxCell: room)
        return VStack(alignment: .leading, spacing: GraphLayout.compactHeaderGap) {
            mediumHeader(reading)
                .frame(height: GraphLayout.compactHeader)
            Spacer(minLength: 0)
            WeekSquares(week: reading.history.thisWeek, fit: row, theme: reading.theme, letters: reading.showsWords)
        }
    }

    /// Large's header, this week in big squares, and the weeks before it
    /// filling the rest.
    private func weekLarge(_ reading: Reading, size: CGSize) -> some View {
        let labels = reading.showsWords
        let row = RowFit(width: size.width, count: 7, gap: 8 * reading.theme.spacing)
        let rowHeight = row.cell + (labels ? WeekSquares.letterSpace : 0)
        let fit = GridFit(
            width: size.width - (labels ? GraphLayout.dayColumn + GraphLayout.dayGap : 0),
            height: size.height - GraphLayout.largeHeader - GraphLayout.largeHeaderGap - rowHeight - GraphLayout.bandGap
                - (labels ? GraphLayout.monthRow + GraphLayout.monthGap : 0),
            gap: reading.gap
        )
        let band = reading.history.bands(1, weeks: fit.columns)[0]
        return VStack(alignment: .leading, spacing: 0) {
            largeHeader(reading, numberSize: 56)
                .frame(height: GraphLayout.largeHeader, alignment: .top)
            WeekSquares(week: reading.history.thisWeek, fit: row, theme: reading.theme, letters: labels)
                .padding(.top, GraphLayout.largeHeaderGap)
            GraphBandView(band: band, fit: fit, labels: labels, theme: reading.theme)
                .padding(.top, GraphLayout.bandGap)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(graphDescription([band], history: reading.history))
        }
    }

    // MARK: - Headers

    /// Small: the streak icon and number on the left, today's check circle
    /// on the right.
    private func smallHeader(_ reading: Reading) -> some View {
        let lead = reading.headline.lead
        let showsIcon = reading.showsWords && stat == .streak && icon != StreakIcon.none
        return HStack(alignment: .center, spacing: 6) {
            HStack(alignment: showsIcon ? .center : .firstTextBaseline, spacing: 5) {
                if showsIcon { iconView(size: 13) }
                number(lead.value, size: 20, lineHeight: 20, tracking: -0.4, theme: reading.theme)
                // The streak is said by its icon; any other number needs a word.
                if reading.showsWords && stat != .streak {
                    caption(lead.shortLabel, size: 12, theme: reading.theme)
                }
            }
            Spacer(minLength: 0)
            TodayCheck(today: reading.history.today, theme: reading.theme)
                .frame(width: 18, height: 18)
        }
        .frame(height: GraphLayout.compactHeader)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    /// Medium, one line: "12 day streak" on the left and today's status on
    /// the right, on one baseline.
    private func mediumHeader(_ reading: Reading) -> some View {
        let lead = reading.headline.lead
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                number(lead.value, size: 22, lineHeight: 22, tracking: -0.44, theme: reading.theme)
                if reading.showsWords {
                    caption(lead.label, size: 12, theme: reading.theme)
                }
            }
            Spacer(minLength: 0)
            TodayStatus(today: reading.history.today, text: reading.headline.status, theme: reading.theme, showsText: reading.showsWords)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    /// Large: the big number and its label on the left; today's status and
    /// two smaller numbers on the right.
    private func largeHeader(_ reading: Reading, numberSize: CGFloat) -> some View {
        let theme = reading.theme
        return HStack(alignment: .top, spacing: 8) {
            bigNumber(reading, size: numberSize, labelSize: 13)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                TodayStatus(today: reading.history.today, text: reading.headline.status, theme: theme, showsText: reading.showsWords)
                if reading.showsWords {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(reading.headline.others, id: \.shortLabel) { other in
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(other.value)
                                    .font(.system(size: 17, weight: .bold, design: theme.numberFontDesign))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(1)
                                Text(other.shortLabel)
                                    .font(.system(size: 11, design: theme.fontDesign))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    /// The icon on the left and today's check circle on the right, over a
    /// big number.
    private func topRow(_ reading: Reading) -> some View {
        HStack(alignment: .center) {
            if reading.showsWords && stat == .streak && icon != StreakIcon.none {
                iconView(size: 15)
            }
            Spacer(minLength: 0)
            TodayCheck(today: reading.history.today, theme: reading.theme)
                .frame(width: 18, height: 18)
        }
        .frame(height: GraphLayout.compactHeader)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        if icon != StreakIcon.none {
            Text(icon).font(.system(size: size))
        }
    }

    /// The lead number with its label underneath. The number sits in a box
    /// 0.95 of its size, the mockup's line height, so the label tucks in
    /// close under the digits.
    private func bigNumber(_ reading: Reading, size: CGFloat, labelSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            number(reading.headline.lead.value, size: size, lineHeight: size * 0.95, tracking: -0.04 * size, theme: reading.theme)
            if reading.showsWords {
                caption(reading.headline.lead.label, size: labelSize, theme: reading.theme)
            }
        }
    }

    /// The number in the look's number font and fill. It keeps its full
    /// height and hangs out of a box `lineHeight` tall, the way CSS sets a
    /// tight line height, and narrows rather than wraps when it's long.
    private func number(_ value: String, size: CGFloat, lineHeight: CGFloat, tracking: CGFloat, theme: WidgetTheme) -> some View {
        Text(value)
            .font(.system(size: size, weight: theme.numberWeight, design: theme.numberFontDesign))
            .tracking(tracking)
            .foregroundStyle(theme.numberFill)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: lineHeight)
            .contentTransition(.numericText())
            .widgetAccentable()
    }

    private func caption(_ text: String, size: CGFloat, theme: WidgetTheme) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The status dot and circle carry "pushed today?" without words at
    /// the small size, and a color says nothing to VoiceOver, so the label
    /// states it outright. The streak is always said, whatever number the
    /// widget shows.
    private func statusDescription(_ reading: Reading) -> String {
        let streak = reading.history.streak
        var text = "\(streak) day\(streak == 1 ? "" : "s") streak. \(reading.history.today.spokenStatus)"
        if stat != .streak {
            let lead = reading.headline.lead
            text += " \(lead.value) \(lead.label)."
        }
        return text
    }

    /// Several hundred colored squares are individually meaningless and
    /// unnavigable, so the graph is one element that states what a sighted
    /// reader takes from the shape of it.
    private func graphDescription(_ bands: [GraphBand], history: StreakHistory) -> String {
        let days = bands.flatMap(\.days).compactMap { $0 }
        let active = days.filter(\.isActive).count
        let off = days.filter { $0.off != nil }.count
        var text = "Contribution graph. \(active) of \(days.count) days with contributions"
        if off > 0 {
            text += ", \(off) day\(off == 1 ? "" : "s") off"
        }
        if let endDate = history.endDate {
            text += ", through \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return text + "."
    }
}

extension StreakHistory.Today {
    /// The few words the Lock Screen shows under the streak.
    var caption: String {
        switch self {
        case .pushed: "committed today"
        case .off(.rest): "rest day"
        case .off(.freeze): "streak frozen"
        case .pending: "not yet today"
        }
    }

    var spokenStatus: String {
        switch self {
        case .pushed: "Committed today."
        case .off(.rest): "Rest day today."
        case .off(.freeze): "Streak frozen today."
        case .pending: "Not committed yet today."
        }
    }
}

/// Small's 18pt circle for today: filled in the look's accent with a check
/// cut out of it once you've pushed, an empty ring while you haven't, and a
/// ring with a dot on a day off.
struct TodayCheck: View {
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        switch today {
        case .pushed:
            CheckCircle().fill(theme.pushed).widgetAccentable()
        case .pending:
            Circle().strokeBorder(theme.pending, lineWidth: 1.5)
        case .off(let kind):
            let color = kind == .freeze ? theme.freeze : theme.pending
            Circle().strokeBorder(color, lineWidth: 1.5)
                .overlay { Circle().fill(color).padding(6) }
        }
    }
}

/// A filled circle with a check cut out of it, so the backdrop shows
/// through the check in every look and on a tinted home screen too. The
/// check is the mockup's: `M5 12.5 l4.5 4.5 L19 7.5` in a 24-unit box,
/// 10/18 of the circle across, with a stroke of 4 units.
struct CheckCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let box = rect.width * 10 / 18
        let origin = CGPoint(x: rect.midX - box / 2, y: rect.midY - box / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x / 24 * box, y: origin.y + y / 24 * box)
        }
        var check = Path()
        check.move(to: point(5, 12.5))
        check.addLine(to: point(9.5, 17))
        check.addLine(to: point(19, 7.5))
        let stroke = check.strokedPath(StrokeStyle(lineWidth: 4 / 24 * box, lineCap: .round, lineJoin: .round))
        return Path(ellipseIn: rect).subtracting(stroke)
    }
}

/// The 7pt dot beside the status words: filled in the accent once you've
/// pushed, an empty ring while you haven't.
struct TodayDot: View {
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        switch today {
        case .pushed:
            Circle().fill(theme.pushed).widgetAccentable()
        case .pending:
            Circle().strokeBorder(theme.pending, lineWidth: 1.5)
        case .off(let kind):
            Circle().strokeBorder(kind == .freeze ? theme.freeze : theme.pending, lineWidth: 1.5)
        }
    }
}

/// The dot and "Pushed today", or what today is instead.
struct TodayStatus: View {
    let today: StreakHistory.Today
    let text: String
    let theme: WidgetTheme
    var showsText = true

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            TodayDot(today: today, theme: theme)
                .frame(width: 7, height: 7)
            if showsText {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(today == .pushed ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// This week, Sunday to Saturday, with the day letters under it. The days
/// still to come are faint dashed outlines, so the shape of the week is
/// there from Sunday on. Today is ringed.
private struct WeekSquares: View {
    let week: (days: [StreakDay?], todayIndex: Int)
    let fit: RowFit
    let theme: WidgetTheme
    var letters = true

    /// The letters' row and the space above it.
    static let letterSpace: CGFloat = 6 + 13

    private static let letterNames: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar.veryShortWeekdaySymbols
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayGrid(
                cells: (0..<7).map { index in
                    DayGrid.Cell(content: week.days[index].map { .day($0) } ?? .upcoming, frame: fit.frame(index))
                },
                size: fit.size,
                theme: theme,
                today: week.todayIndex
            )
            if letters {
                HStack(spacing: fit.gap) {
                    ForEach(0..<7, id: \.self) { index in
                        let isToday = index == week.todayIndex
                        Text(Self.letterNames[index])
                            .font(.system(size: 11, weight: isToday ? .bold : .medium, design: theme.fontDesign))
                            .foregroundStyle(isToday ? theme.primaryText : theme.secondaryText)
                            .frame(width: fit.cell, height: 13)
                    }
                }
            }
        }
    }
}

/// The last seven days in a row, today on the right. Today is ringed until
/// you push, since it's the one square a streak widget is really about. On a
/// day off there's nothing owed, so it wears the day-off mark instead. Used
/// by the Lock Screen, which keeps its own look.
struct WeekStrip: View {
    let days: [StreakDay]
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 4 * theme.spacing) {
            ForEach(days.indices, id: \.self) { index in
                DayCell(day: days[index], theme: theme)
                    .overlay {
                        if index == days.count - 1 && today == .pending {
                            CellShape(theme)
                                .strokeBorder(theme.pending, lineWidth: 1.5)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .widgetAccentable(days[index].isActive)
            }
        }
    }
}

/// A widget as it sits on the home screen, for showing styles inside the
/// app, where there's no widget container to supply margins and a backdrop.
struct WidgetPreviewCard: View {
    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    let style: WidgetStyle
    let layout: WidgetLayout
    var stat: WidgetStat = .streak
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    var dayOffMark: DayOffMark = AppConfig.dayOffMark
    var now = Date()

    /// Home-screen sizes on the larger iPhones, in points.
    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        default: CGSize(width: 364, height: 170)
        }
    }

    static let cornerRadius: CGFloat = 22

    var body: some View {
        let size = Self.size(for: family)
        PushedWidgetView(
            snapshot: snapshot,
            family: family,
            style: style,
            layout: layout,
            stat: stat,
            icon: icon,
            custom: custom,
            protection: protection,
            dayOffMark: dayOffMark,
            now: now
        )
        .frame(width: size.width, height: size.height)
        .background { WidgetBackground(style: style, custom: custom) }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}
