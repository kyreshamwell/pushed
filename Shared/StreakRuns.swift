import Foundation

/// A stretch of days that counted toward one streak, as positions in
/// `StreakHistory.days`.
struct StreakRun: Equatable, Sendable {
    /// The run's first pushed day.
    let start: Int
    /// The last day the run reaches: today for the live streak, the last
    /// pushed day for one that's over.
    let end: Int
    /// Pushed days in it. Days off carry a run without adding to it, so this
    /// is the number the streak shows, not the span of the dates.
    let length: Int
}

/// What happened over a run.
struct StreakRunStats: Equatable, Sendable {
    var pushedDays = 0
    var restDays = 0
    var freezes = 0
    /// Nil when the snapshot has no daily counts (data saved before 1.3).
    var contributions: Int?
}

/// One square on a streak calendar.
struct StreakCalendarDay: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case pushed(level: Int)
        case rest
        case freeze
        /// A past day with nothing on it, or one Pushed has no data for.
        case empty
        case future
    }

    let date: Date
    /// Day of the month.
    let number: Int
    let kind: Kind
    let inRun: Bool
    let isToday: Bool

    var id: Date { date }
}

/// One month of a streak calendar, Sunday first like the graph.
struct StreakCalendarMonth: Equatable, Sendable, Identifiable {
    /// The first of the month.
    let start: Date
    /// Blank squares before the 1st, so it lands under its weekday.
    let leadingBlanks: Int
    let days: [StreakCalendarDay]

    var id: Date { start }
}

extension StreakHistory {
    /// The live streak, from its first pushed day through today. Nil once the
    /// streak is broken, or before there is one.
    var currentRun: StreakRun? {
        let length = streak
        guard length > 0, let todayIndex, let last = days.lastIndex(where: \.isActive) else { return nil }
        return StreakRun(start: firstPushedDay(endingAt: last), end: max(todayIndex, last), length: length)
    }

    /// The run behind `bestStreak`, counted the same way. A tie goes to the
    /// later run, so a current streak that matches the record is the record.
    var bestRun: StreakRun? {
        let last = todayIndex.map { min($0, days.count - 1) } ?? days.count - 1
        guard last >= 0 else { return nil }
        var best: StreakRun?
        var length = 0
        var start = 0
        for index in 0...last {
            let day = days[index]
            if day.isActive {
                if length == 0 { start = index }
                length += 1
                if length >= (best?.length ?? 1) {
                    best = StreakRun(start: start, end: index, length: length)
                }
            } else if day.off == nil && index != todayIndex {
                length = 0
            }
        }
        return best
    }

    /// Walks back from a pushed day over pushed days and days off to the
    /// first pushed day of its run.
    private func firstPushedDay(endingAt last: Int) -> Int {
        var first = last
        var index = last
        while index >= 0 {
            if days[index].isActive {
                first = index
            } else if days[index].off == nil {
                break
            }
            index -= 1
        }
        return first
    }

    /// Pushed days, rest days, freezes and contributions over a run.
    /// `counts` lines up with the snapshot's levels, which `days` starts with.
    func stats(of run: StreakRun, counts: [Int]?) -> StreakRunStats {
        var stats = StreakRunStats()
        let range = max(run.start, 0)...min(run.end, days.count - 1)
        for index in range {
            let day = days[index]
            if day.isActive {
                stats.pushedDays += 1
            } else if day.off == .rest {
                stats.restDays += 1
            } else if day.off == .freeze {
                stats.freezes += 1
            }
        }
        if let counts {
            stats.contributions = range.reduce(0) { total, index in
                total + (counts.indices.contains(index) ? counts[index] : 0)
            }
        }
        return stats
    }

    /// The date of a position in `days`.
    func date(at index: Int) -> Date? {
        guard let todayIndex else { return nil }
        return date(daysAgo: todayIndex - index)
    }

    /// The position of a date in `days`, if it's inside the window.
    func index(of date: Date) -> Int? {
        guard let todayIndex, let today = self.date(daysAgo: 0),
              let back = calendar.dateComponents(
                  [.day], from: calendar.startOfDay(for: date), to: today
              ).day else { return nil }
        let index = todayIndex - back
        return days.indices.contains(index) ? index : nil
    }

    /// Every month a run touches, each day marked pushed, rest, freeze,
    /// empty or still to come, and whether it falls inside the run.
    func calendarMonths(for run: StreakRun) -> [StreakCalendarMonth] {
        guard let first = date(at: run.start), let last = date(at: run.end),
              let today = date(daysAgo: 0),
              var month = calendar.dateInterval(of: .month, for: first)?.start,
              let lastMonth = calendar.dateInterval(of: .month, for: last)?.start else { return [] }

        var months: [StreakCalendarMonth] = []
        while month <= lastMonth {
            guard let length = calendar.range(of: .day, in: .month, for: month)?.count else { break }
            let days = (0..<length).compactMap { offset -> StreakCalendarDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: month) else { return nil }
                return calendarDay(date, run: run, today: today)
            }
            months.append(StreakCalendarMonth(
                start: month,
                leadingBlanks: calendar.component(.weekday, from: month) - 1,
                days: days
            ))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return months
    }

    private func calendarDay(_ date: Date, run: StreakRun, today: Date) -> StreakCalendarDay {
        let number = calendar.component(.day, from: date)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        guard date <= today || isToday else {
            return StreakCalendarDay(date: date, number: number, kind: .future, inRun: false, isToday: false)
        }
        guard let index = index(of: date) else {
            return StreakCalendarDay(date: date, number: number, kind: .empty, inRun: false, isToday: isToday)
        }
        let day = days[index]
        let kind: StreakCalendarDay.Kind
        if day.isActive {
            kind = .pushed(level: day.level)
        } else if day.off == .rest {
            kind = .rest
        } else if day.off == .freeze {
            kind = .freeze
        } else {
            kind = .empty
        }
        let inRun = (run.start...run.end).contains(index)
        return StreakCalendarDay(date: date, number: number, kind: kind, inRun: inRun, isToday: isToday)
    }
}

// MARK: - Milestones

enum StreakMilestone {
    /// The next milestone above `streak`, from the same list the
    /// celebration notifications use. Nil once they're all passed.
    static func next(after streak: Int) -> Int? {
        NotificationPlanner.milestones.first { $0 > streak }
    }

    /// How far `streak` is toward `next(after:)`, 0 to 1.
    static func progress(_ streak: Int) -> Double {
        guard let next = next(after: streak) else { return 1 }
        return min(max(Double(streak) / Double(next), 0), 1)
    }
}
