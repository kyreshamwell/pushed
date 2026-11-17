import CoreGraphics
import Foundation
import WidgetKit

/// Squares sized to fill an area exactly. Seven rows reach from top to
/// bottom, which sets the square size; then as many whole weeks as fit go
/// across, and the gaps stretch a little so the grid meets every edge.
struct GridFit: Equatable {
    /// The side of one square, in whole points.
    var cell: CGFloat
    /// Weeks across.
    var columns: Int
    var columnGap: CGFloat
    var rowGap: CGFloat

    /// The narrowest gap between squares, before it stretches.
    static let gap: CGFloat = 3

    init(width: CGFloat, height: CGFloat, gap: CGFloat = GridFit.gap) {
        let cell = max(floor((height - 6 * gap) / 7), 1)
        let columns = max(Int(floor((width + gap) / (cell + gap))), 1)
        self.cell = cell
        self.columns = columns
        columnGap = columns > 1 ? (width - CGFloat(columns) * cell) / CGFloat(columns - 1) : 0
        rowGap = max((height - 7 * cell) / 6, 0)
    }

    var width: CGFloat { CGFloat(columns) * cell + CGFloat(max(columns - 1, 0)) * columnGap }
    var height: CGFloat { 7 * cell + 6 * rowGap }
    var size: CGSize { CGSize(width: width, height: height) }

    /// From one week's left edge to the next.
    var columnStep: CGFloat { cell + columnGap }
    var rowStep: CGFloat { cell + rowGap }

    /// Where a day goes: its week across, its weekday down (Sunday is 0).
    func frame(column: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(column) * columnStep, y: CGFloat(row) * rowStep, width: cell, height: cell)
    }

    /// Day `index` of a run that starts on a Sunday, seven to a week.
    func frame(index: Int) -> CGRect {
        frame(column: index / 7, row: index % 7)
    }
}

/// Where everything goes in the Graph layout at one widget size, ported
/// from the approved mockup. The header sits on top, then one row of weeks
/// fills the rest; Large splits its weeks into two rows, older on top, with
/// month names over each and Mon, Wed, Fri down the side.
struct GraphLayout: Equatable {
    var header: CGFloat
    /// Between the header and the squares.
    var headerGap: CGFloat
    /// Rows of weeks: one, or two on Large.
    var bands: Int
    var bandGap: CGFloat
    var labels: Bool
    var fit: GridFit

    static let compactHeader: CGFloat = 22
    static let compactHeaderGap: CGFloat = 10
    static let largeHeader: CGFloat = 88
    static let largeHeaderGap: CGFloat = 12
    static let bandGap: CGFloat = 14
    /// Month names: a 12pt row, 3pt above the squares.
    static let monthRow: CGFloat = 12
    static let monthGap: CGFloat = 3
    /// Day names: a 22pt column, 4pt left of the squares.
    static let dayColumn: CGFloat = 22
    static let dayGap: CGFloat = 4

    /// `size` is the widget less its margins. `labels` is whether Large has
    /// room for words at all (a minimal style has none), and `gap` is the
    /// narrowest gap between squares.
    init(family: WidgetFamily, size: CGSize, labels: Bool = true, gap: CGFloat = GridFit.gap) {
        if family == .systemLarge || family == .systemExtraLarge {
            header = Self.largeHeader
            headerGap = Self.largeHeaderGap
            bands = 2
            bandGap = Self.bandGap
            self.labels = labels
            let block = (size.height - header - headerGap - bandGap) / 2
            let gridHeight = block - (labels ? Self.monthRow + Self.monthGap : 0)
            let gridWidth = size.width - (labels ? Self.dayColumn + Self.dayGap : 0)
            fit = GridFit(width: gridWidth, height: gridHeight, gap: gap)
        } else {
            header = Self.compactHeader
            headerGap = Self.compactHeaderGap
            bands = 1
            bandGap = 0
            self.labels = false
            fit = GridFit(width: size.width, height: size.height - header - headerGap, gap: gap)
        }
    }

    /// Every week the widget shows.
    var weeks: Int { fit.columns * bands }
}

/// One row of weeks, as drawn: the days column by column from a Sunday.
struct GraphBand: Equatable {
    /// Seven a week, Sunday first. Nil where the history doesn't reach back
    /// that far. The newest week stops at the newest day.
    var days: [StreakDay?]
    /// Where today sits in `days`, when it's in this row.
    var today: Int?
    /// The Sunday the first week starts on. Nil without a readable date.
    var start: Date?
    var weeks: Int

    /// Every day that comes after today, which only happens when GitHub's
    /// date runs ahead of the phone's. Those aren't missed yet.
    func isAfterToday(_ index: Int) -> Bool {
        guard let today else { return false }
        return index > today
    }
}

/// A month name over the week it starts in.
struct MonthLabel: Equatable {
    var week: Int
    var text: String
}

extension GraphBand {
    private static let monthNames: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.shortMonthSymbols
    }()

    /// A name over each week whose Sunday is in a new month, as GitHub
    /// labels its graph. A name with the next one less than three weeks on
    /// is dropped, so two never crowd each other.
    func monthLabels(calendar: Calendar = Calendar(identifier: .gregorian)) -> [MonthLabel] {
        guard let start else { return [] }
        var marks: [(week: Int, month: Int)] = []
        for week in 0..<weeks {
            guard let sunday = calendar.date(byAdding: .day, value: week * 7, to: start) else { continue }
            let month = calendar.component(.month, from: sunday)
            if marks.last?.month != month {
                marks.append((week, month))
            }
        }
        return marks.indices.compactMap { index in
            let mark = marks[index]
            if index + 1 < marks.count, marks[index + 1].week - mark.week < 3 { return nil }
            return MonthLabel(week: mark.week, text: Self.monthNames[mark.month - 1])
        }
    }
}

extension StreakHistory {
    /// The newest weeks, split into `count` rows of `weeks` weeks each,
    /// oldest row first. The last row ends with the newest day, so on any
    /// normal day its last week is this one and ends today.
    func bands(_ count: Int, weeks: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> [GraphBand] {
        let rows = max(count, 1)
        let weeks = max(weeks, 1)
        guard !days.isEmpty else {
            return Array(repeating: GraphBand(days: Array(repeating: nil, count: weeks * 7), today: nil, start: nil, weeks: weeks), count: rows)
        }
        let last = days.count - 1
        // Index 0 is a Sunday, so a week starts on every multiple of seven.
        let newestWeek = last - last % 7
        let first = newestWeek - (rows * weeks - 1) * 7

        return (0..<rows).map { row in
            let start = first + row * weeks * 7
            let end = row == rows - 1 ? last + 1 : start + weeks * 7
            let shown = (start..<end).map { $0 >= 0 ? days[$0] : nil }
            let today = todayIndex.flatMap { (start..<end).contains($0) ? $0 - start : nil }
            let startDate = endDate.flatMap { calendar.date(byAdding: .day, value: start - last, to: calendar.startOfDay(for: $0)) }
            return GraphBand(days: shown, today: today, start: startDate, weeks: weeks)
        }
    }
}

// MARK: - The header's words

/// The numbers and words a widget's header shows, worked out once.
struct WidgetHeadline: Equatable {
    struct Stat: Equatable {
        var value: String
        /// Beside or under the number: "day streak".
        var label: String
        /// Under a small number in Large's corner, or after the number on
        /// Small when it isn't the streak: "best".
        var shortLabel: String
    }

    /// The number the widget leads with, picked by Show.
    var lead: Stat
    /// Large's two smaller numbers: the most telling ones that aren't the lead.
    var others: [Stat]
    /// "Pushed today", or what today is instead.
    var status: String

    init(history: StreakHistory, total: Int, stat: WidgetStat) {
        lead = Self.stat(stat, history: history, total: total)
        others = Self.others(for: stat).map { Self.stat($0, history: history, total: total) }
        status = history.today.status
    }

    /// Streak, best and this year in that order, less whichever leads.
    static func others(for lead: WidgetStat) -> [WidgetStat] {
        Array([WidgetStat.streak, .best, .year].filter { $0 != lead }.prefix(2))
    }

    static func stat(_ stat: WidgetStat, history: StreakHistory, total: Int) -> Stat {
        switch stat {
        case .streak:
            return Stat(value: "\(history.streak)", label: "day streak", shortLabel: "streak")
        case .best:
            return Stat(value: "\(history.bestStreak)", label: "best streak", shortLabel: "best")
        case .week:
            let pushed = history.pushedThisWeek
            return Stat(value: "\(pushed)", label: pushed == 1 ? "day this week" : "days this week", shortLabel: "this week")
        case .year:
            return Stat(value: total.formatted(), label: "this year", shortLabel: "this year")
        }
    }
}

extension StreakHistory.Today {
    /// The words beside the header's status dot.
    var status: String {
        switch self {
        case .pushed: "Pushed today"
        case .off(.rest): "Rest day"
        case .off(.freeze): "Streak frozen"
        case .pending: "Not yet today"
        }
    }
}

// MARK: - Marks

/// What a day shows in the Marks look.
enum DayMark: Equatable {
    /// Pushed: a dot, brighter the busier the day.
    case dot(level: Int)
    /// Today, not pushed yet: nothing but the ring around it.
    case open
    case freeze
    case rest
    /// An empty day that wasn't a day off. `endedStreak` is the one a
    /// streak ended on, which a custom missed-day color picks out.
    case missed(endedStreak: Bool)
    /// No symbol: before the history starts, or after today.
    case blank

    /// Days off and pushes come from the same rest day and freeze rules as
    /// every other look; anything else empty before today is a miss.
    init(_ day: StreakDay?, isToday: Bool, isAfterToday: Bool = false) {
        guard let day, !isAfterToday else {
            self = .blank
            return
        }
        if day.isActive {
            self = .dot(level: min(day.level, 4))
        } else if isToday {
            self = .open
        } else if let off = day.off {
            self = off == .freeze ? .freeze : .rest
        } else {
            self = .missed(endedStreak: day.endedStreak)
        }
    }
}
