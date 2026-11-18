import SwiftUI
import UIKit

/// The sheets behind the three numbers on Home.
enum Insight: String, Identifiable {
    case current, best, year

    var id: String { rawValue }
}

// MARK: - Colors

/// The calendar and graph colors on these sheets: GitHub's greens, and
/// quiet greys for everything else, in both appearances.
private enum InsightColors {
    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    private static let greens: [(dark: UInt32, light: UInt32)] = [
        (0x2F3640, 0xEBEDF0), (0x0E4429, 0x9BE9A8), (0x006D32, 0x40C463), (0x26A641, 0x30A14E), (0x39D353, 0x216E39),
    ]

    static func level(_ level: Int) -> Color {
        let pair = greens[min(max(level, 0), 4)]
        return dynamic(dark: pair.dark, light: pair.light)
    }

    /// Text on a green square: dark on the bright greens, light on the deep ones.
    static func ink(onLevel level: Int) -> Color {
        level >= 3 ? dynamic(dark: 0x04150A, light: 0xFFFFFF) : dynamic(dark: 0xE6EDF3, light: 0x0A3D1A)
    }

    /// A day with nothing on it, sitting on a raised card.
    static let quietDay = dynamic(dark: 0x232326, light: 0xFFFFFF)
    static let rest = dynamic(dark: 0x3A3A3C, light: 0xD1D1D6)
    static let restInk = dynamic(dark: 0xD1D1D6, light: 0x3A3A3C)
    static let freeze = dynamic(dark: 0x1E3A4C, light: 0xCFEFFC)
    static let freezeInk = dynamic(dark: 0x7DD3FC, light: 0x0369A1)
    /// The empty part of a bar on a raised card.
    static let barTrack = dynamic(dark: 0x3A3A3C, light: 0xD1D1D6)
    /// The chosen year in the switcher.
    static let selectedSegment = dynamic(dark: 0x636366, light: 0xFFFFFF)
}

// MARK: - Shared pieces

/// The sheet's frame: a title with Done, then scrolling content.
private struct InsightSheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.card)
        .tint(.pushedGreen)
    }
}

/// The big number at the top of a sheet, with a line under it.
private struct HeadlineNumber: View {
    let value: Int
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.formatted())
                    .font(.system(size: 64, weight: .heavy))
                    .kerning(-2)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(value == 1 ? "day" : "days")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small number on a raised tile.
private struct InsightTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A labelled bar that fills in when the sheet opens.
private struct ProgressRow: View {
    let title: String
    let detail: String
    let progress: Double
    @State private var shown = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
            }
            .font(.footnote)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.raised)
                    Capsule()
                        .fill(Color.pushedGreen)
                        .frame(width: geometry.size.width * shown)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.15)) { shown = progress }
        }
        .onChange(of: progress) { _, value in
            withAnimation(.snappy) { shown = value }
        }
    }
}

/// One month of a streak calendar.
private struct StreakMonthView: View {
    let month: StreakCalendarMonth
    var compact = false
    var ringsToday = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(month.start.formatted(.dateTime.month(.wide).year()))
                .font(compact ? .subheadline.weight(.semibold) : .subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 5 : 6), count: 7), spacing: compact ? 5 : 6) {
                if !compact {
                    ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: cellHeight)
                }
                ForEach(month.days) { day in
                    cell(day)
                }
            }
        }
        .padding(compact ? 12 : 14)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cellHeight: CGFloat { compact ? 24 : 38 }

    private func cell(_ day: StreakCalendarDay) -> some View {
        let look = style(day)
        return Text(look.label)
            .font(.system(size: compact ? 10 : 13, weight: look.bold ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(look.ink)
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(look.fill, in: RoundedRectangle(cornerRadius: compact ? 6 : 9, style: .continuous))
            .overlay {
                if ringsToday && day.isToday {
                    RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .padding(-3)
                }
            }
            .opacity(day.kind == .future ? 0.35 : 1)
            .accessibilityLabel(accessibility(day))
    }

    private func style(_ day: StreakCalendarDay) -> (label: String, fill: Color, ink: Color, bold: Bool) {
        let number = "\(day.number)"
        if day.kind == .future {
            return (number, .clear, .secondary, false)
        }
        guard day.inRun else {
            return (number, InsightColors.quietDay, Color(uiColor: compact ? .tertiaryLabel : .secondaryLabel), false)
        }
        switch day.kind {
        case .pushed(let level):
            return (number, InsightColors.level(level), InsightColors.ink(onLevel: level), true)
        case .rest:
            return ("R", InsightColors.rest, InsightColors.restInk, true)
        case .freeze:
            return ("F", InsightColors.freeze, InsightColors.freezeInk, true)
        case .empty, .future:
            return (number, InsightColors.quietDay, .secondary, false)
        }
    }

    private func accessibility(_ day: StreakCalendarDay) -> String {
        let date = day.date.formatted(.dateTime.month(.wide).day())
        let what: String = switch day.kind {
        case .pushed: "pushed"
        case .rest: "rest day"
        case .freeze: "freeze"
        case .empty: "nothing pushed"
        case .future: "still to come"
        }
        return "\(date), \(what)\(day.isToday ? ", today" : "")"
    }
}

private extension Date {
    /// "Monday, Nov 2", with the year when it isn't this one.
    var longDay: String {
        let sameYear = Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            : formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }
}

// MARK: - Current streak

struct CurrentStreakSheet: View {
    let history: StreakHistory
    let counts: [Int]?

    var body: some View {
        InsightSheetFrame(title: "Current streak") {
            if let run = history.currentRun, let start = history.date(at: run.start) {
                HeadlineNumber(value: run.length, caption: "Since \(start.longDay)")
                ForEach(history.calendarMonths(for: run)) { month in
                    StreakMonthView(month: month)
                }
                legend
                tiles(history.stats(of: run, counts: counts))
                milestone(run.length)
            } else {
                emptyState
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Text("R rest day")
            Text("F freeze")
            Text("Ring is today")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, -8)
    }

    private func tiles(_ stats: StreakRunStats) -> some View {
        HStack(spacing: 8) {
            // Data saved before 1.3 has no daily counts until the next sync,
            // so the days pushed stand in.
            if let contributions = stats.contributions {
                InsightTile(value: contributions.formatted(), label: "Contributions")
            } else {
                InsightTile(value: stats.pushedDays.formatted(), label: "Days pushed")
            }
            InsightTile(value: "\(stats.restDays)", label: stats.restDays == 1 ? "Rest day" : "Rest days")
            InsightTile(value: "\(stats.freezes)", label: stats.freezes == 1 ? "Freeze used" : "Freezes used")
        }
    }

    @ViewBuilder
    private func milestone(_ streak: Int) -> some View {
        if let next = StreakMilestone.next(after: streak) {
            ProgressRow(
                title: "Next milestone: \(next) days",
                detail: "\(next - streak) to go",
                progress: StreakMilestone.progress(streak)
            )
        } else {
            ProgressRow(title: "Every milestone reached", detail: "Over a year", progress: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.pushedGreen)
                .frame(width: 72, height: 72)
                .background(Color.pushedGreen.opacity(0.16), in: Circle())
            Text("No streak right now")
                .font(.title3.weight(.bold))
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let next = StreakMilestone.next(after: 0) {
                Text("Your first milestone is \(next) days.")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.raised, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyMessage: String {
        let last = history.streakBeforeBreak
        guard last > 0 else { return "Push something today and your streak starts here, one day at a time." }
        return "Your last streak ran \(last) \(last == 1 ? "day" : "days"). Push something today to start a new one."
    }
}

// MARK: - Best streak

struct BestStreakSheet: View {
    let history: StreakHistory

    var body: some View {
        InsightSheetFrame(title: "Best streak") {
            if let best = history.bestRun {
                HeadlineNumber(value: best.length, caption: span(best))
                ForEach(history.calendarMonths(for: best)) { month in
                    StreakMonthView(month: month, compact: true, ringsToday: false)
                }
                comparison(best)
                Text("Counted over the last year, the same way as your widget.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    Text("No streaks yet")
                        .font(.title3.weight(.bold))
                    Text("Your longest run of pushed days will show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    private var isCurrent: Bool {
        guard let best = history.bestRun, let current = history.currentRun else { return false }
        return best.start == current.start
    }

    /// "Mar 3 to Apr 12, 2026", or "Mar 3, 2026 to today" for a live run.
    private func span(_ run: StreakRun) -> String {
        guard let start = history.date(at: run.start), let end = history.date(at: run.end) else { return "" }
        if isCurrent {
            return "\(start.formatted(.dateTime.month(.abbreviated).day().year())) to today"
        }
        let sameYear = Calendar.current.isDate(start, equalTo: end, toGranularity: .year)
        let from = sameYear
            ? start.formatted(.dateTime.month(.abbreviated).day())
            : start.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(from) to \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    @ViewBuilder
    private func comparison(_ best: StreakRun) -> some View {
        if isCurrent {
            ProgressRow(title: "This is your best streak", detail: "Every day sets a new record", progress: 1)
        } else {
            let current = history.streak
            let toBeat = best.length - current + 1
            ProgressRow(
                title: "You're at \(current)",
                detail: "\(toBeat) more \(toBeat == 1 ? "day" : "days") to beat it",
                progress: Double(current) / Double(max(best.length, 1))
            )
        }
    }
}

// MARK: - This year

struct YearSheet: View {
    @State var model: YearHistoryModel
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var openMonth: Int? = Calendar.current.component(.month, from: Date())

    private let thisYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        InsightSheetFrame(title: "Your year") {
            if model.years.count > 1 {
                switcher
            }
            switch model.phase(for: selectedYear) {
            case .loading:
                loading
            case .failed(let message):
                failure(message)
            case .loaded(let summary):
                yearContent(summary)
            }
        }
        .task { await model.loadYears() }
        .task(id: selectedYear) { await model.load(selectedYear) }
        .sensoryFeedback(.selection, trigger: selectedYear)
        .sensoryFeedback(.selection, trigger: openMonth)
    }

    // MARK: Switcher

    private var switcher: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(model.years, id: \.self) { year in
                    segment(year).frame(minWidth: 58, maxWidth: .infinity)
                }
            }
            .padding(2)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.years, id: \.self) { year in
                            segment(year).frame(width: 64).id(year)
                        }
                    }
                    .padding(2)
                }
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onAppear { proxy.scrollTo(selectedYear, anchor: .trailing) }
            }
        }
    }

    private func segment(_ year: Int) -> some View {
        let selected = year == selectedYear
        return Button {
            withAnimation(.snappy) {
                selectedYear = year
                openMonth = year == thisYear ? Calendar.current.component(.month, from: Date()) : 1
            }
        } label: {
            Text(String(year))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(InsightColors.selectedSegment)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: States

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(String(selectedYear)) from GitHub")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Couldn't load \(String(selectedYear))")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load(selectedYear) }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: The year

    @ViewBuilder
    private func yearContent(_ summary: YearSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            InsightTile(value: summary.total.formatted(), label: "Contributions")
            InsightTile(value: summary.activeDays.formatted(), label: "Active days")
            InsightTile(value: days(summary.longestRun), label: "Longest run")
            InsightTile(value: summary.busiestMonth.map(monthName) ?? "None", label: "Busiest month")
        }
        SheetLabel(text: "By month")
            .padding(.bottom, -8)
        let most = max(summary.months.map(\.total).max() ?? 0, 1)
        VStack(spacing: 6) {
            ForEach(summary.months) { month in
                monthRow(month, most: most, today: summary.todayKey)
            }
        }
    }

    private func monthRow(_ month: MonthSummary, most: Int, today: String) -> some View {
        let open = openMonth == month.month && !month.isFuture
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    openMonth = open ? nil : month.month
                }
            } label: {
                HStack(spacing: 10) {
                    Text(shortMonth(month.month))
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(InsightColors.barTrack)
                            Capsule()
                                .fill(Color.pushedGreen)
                                .frame(width: geometry.size.width * CGFloat(month.total) / CGFloat(most))
                        }
                    }
                    .frame(height: 8)
                    Text(month.total.formatted())
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(month.isFuture)
            .accessibilityLabel("\(monthName(month.month)), \(month.total) contributions")
            .accessibilityHint(month.isFuture ? "" : (open ? "Hides the month" : "Shows the month"))

            if open {
                monthDetail(month, today: today)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(month.isFuture ? 0.4 : 1)
    }

    private func monthDetail(_ month: MonthSummary, today: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            miniGraph(month, today: today)
            HStack(alignment: .top, spacing: 6) {
                detailStat(month.activeDays.formatted(), "active days")
                detailStat(month.busiestDay.map(dayName) ?? "None", "busiest day")
                detailStat(days(month.longestRun), "longest run")
            }
        }
    }

    /// The month as weeks, Sunday at the top, like the graph on the widget.
    private func miniGraph(_ month: MonthSummary, today: String) -> some View {
        let cells: [YearDay?] = Array(repeating: nil, count: month.leadingBlanks) + month.days.map { $0 }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return HStack(alignment: .top, spacing: 3) {
            ForEach(weeks.indices, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(weeks[week].indices, id: \.self) { index in
                        let day = weeks[week][index]
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(fill(day, today: today))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ day: YearDay?, today: String) -> Color {
        guard let day else { return .clear }
        if day.date > today { return InsightColors.quietDay }
        return InsightColors.level(day.level)
    }

    private func detailStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Words

    private func days(_ count: Int) -> String {
        "\(count) \(count == 1 ? "day" : "days")"
    }

    private func monthName(_ month: Int) -> String {
        Calendar.current.monthSymbols[month - 1]
    }

    private func shortMonth(_ month: Int) -> String {
        Calendar.current.shortMonthSymbols[month - 1]
    }

    private func dayName(_ day: YearDay) -> String {
        guard let date = ContributionCalendar.dateFormatter.date(from: day.date) else { return day.date }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
