import Foundation

/// One day of a year, as GitHub counts it.
struct YearDay: Codable, Equatable, Sendable, Identifiable {
    /// "yyyy-MM-dd".
    let date: String
    let count: Int
    /// GitHub's shade, 0 to 4.
    let level: Int

    var id: String { date }
}

/// A calendar year of contributions, January to December.
struct ContributionYear: Codable, Equatable, Sendable {
    let year: Int
    /// Oldest first, only this year's dates. A date missing from the list
    /// had no contributions.
    let days: [YearDay]

    init(year: Int, days: [YearDay]) {
        self.year = year
        let prefix = "\(year)-"
        self.days = days.filter { $0.date.hasPrefix(prefix) }.sorted { $0.date < $1.date }
    }

    /// GitHub's calendar pads its first and last weeks with days outside the
    /// range asked for, so those are dropped.
    init(year: Int, calendar: ContributionCalendar) {
        self.init(year: year, days: calendar.days.map {
            YearDay(date: $0.date, count: $0.contributionCount, level: $0.level)
        })
    }

    /// The year read out of a snapshot, which holds the last 52 weeks or so.
    /// Nil when the snapshot has no daily counts or doesn't reach back to
    /// January 1, since a year missing its start would undercount.
    init?(snapshot: ContributionSnapshot, year: Int) {
        guard let counts = snapshot.recentCounts,
              counts.count == snapshot.recentLevels.count,
              let end = snapshot.endDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let formatter = ContributionCalendar.dateFormatter
        guard let firstOfYear = formatter.date(from: String(format: "%04d-01-01", year)),
              let first = calendar.date(byAdding: .day, value: -(counts.count - 1), to: end),
              first <= firstOfYear else { return nil }

        let days = counts.indices.compactMap { index -> YearDay? in
            guard let date = calendar.date(byAdding: .day, value: index, to: first) else { return nil }
            return YearDay(date: formatter.string(from: date), count: counts[index], level: snapshot.recentLevels[index])
        }
        self.init(year: year, days: days)
    }
}

// MARK: - The numbers

/// One month of a year: its days, its total and its records.
struct MonthSummary: Equatable, Sendable, Identifiable {
    /// 1 is January.
    let month: Int
    /// Every date of the month, empty ones included, oldest first.
    let days: [YearDay]
    /// Blank squares before the 1st, so it lands under its weekday.
    let leadingBlanks: Int
    let total: Int
    let activeDays: Int
    /// The day with the most contributions; the earlier one on a tie.
    let busiestDay: YearDay?
    /// The most days in a row with a contribution, inside this month.
    let longestRun: Int
    /// The whole month is still to come.
    let isFuture: Bool

    var id: Int { month }
}

/// What a year adds up to. Days after `today` count as still to come.
struct YearSummary: Equatable, Sendable {
    let year: Int
    let total: Int
    let activeDays: Int
    /// The most days in a row with a contribution. This is GitHub's own count,
    /// without rest days or freezes, since those are only kept for a year.
    let longestRun: Int
    /// 1 is January. Nil for a year with nothing in it.
    let busiestMonth: Int?
    let busiestDay: YearDay?
    let months: [MonthSummary]
    /// "yyyy-MM-dd" of today, for telling past squares from future ones.
    let todayKey: String

    init(_ data: ContributionYear, today: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        let formatter = ContributionCalendar.dateFormatter
        let todayKey = formatter.string(from: today)
        let byDate = Dictionary(data.days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })

        var months: [MonthSummary] = []
        var run = 0
        var longest = 0
        for month in 1...12 {
            let firstKey = String(format: "%04d-%02d-01", data.year, month)
            guard let first = formatter.date(from: firstKey),
                  let length = calendar.range(of: .day, in: .month, for: first)?.count else { continue }

            var days: [YearDay] = []
            var monthRun = 0
            var monthLongest = 0
            for offset in 0..<length {
                guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
                let key = formatter.string(from: date)
                let day = byDate[key] ?? YearDay(date: key, count: 0, level: 0)
                days.append(day)
                guard key <= todayKey else { continue }
                if day.count > 0 {
                    run += 1
                    monthRun += 1
                } else {
                    run = 0
                    monthRun = 0
                }
                longest = max(longest, run)
                monthLongest = max(monthLongest, monthRun)
            }

            let past = days.filter { $0.date <= todayKey }
            months.append(MonthSummary(
                month: month,
                days: days,
                leadingBlanks: calendar.component(.weekday, from: first) - 1,
                total: past.reduce(0) { $0 + $1.count },
                activeDays: past.filter { $0.count > 0 }.count,
                busiestDay: Self.busiest(past),
                longestRun: monthLongest,
                isFuture: firstKey > todayKey
            ))
        }

        year = data.year
        self.months = months
        self.todayKey = todayKey
        total = months.reduce(0) { $0 + $1.total }
        activeDays = months.reduce(0) { $0 + $1.activeDays }
        longestRun = longest
        busiestDay = Self.busiest(months.compactMap(\.busiestDay))
        // Strictly greater, so a tie keeps the earlier month.
        busiestMonth = months.reduce(nil as MonthSummary?) { best, month in
            month.total > (best?.total ?? 0) ? month : best
        }?.month
    }

    private static func busiest(_ days: [YearDay]) -> YearDay? {
        days.reduce(nil as YearDay?) { best, day in
            day.count > (best?.count ?? 0) ? day : best
        }
    }
}

// MARK: - Sample years

extension ContributionYear {
    /// How many years before this one the demo account joined.
    static let sampleYearsBack = 3

    /// A believable past year for demo mode and previews: busier each year
    /// since joining, quieter at weekends, with a busy spring and a slow
    /// August. Deterministic, so screenshots don't reshuffle.
    static func sample(year: Int, joinYear: Int) -> ContributionYear {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = ContributionCalendar.dateFormatter
        guard let first = formatter.date(from: String(format: "%04d-01-01", year)),
              let length = calendar.range(of: .day, in: .year, for: first)?.count else {
            return ContributionYear(year: year, days: [])
        }
        let growth = Double(max(year - joinYear, 0)) * 0.1

        let days = (0..<length).compactMap { offset -> YearDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let month = calendar.component(.month, from: date)
            let weekday = calendar.component(.weekday, from: date)
            let seed = year &* 1000 &+ offset
            // The account opens in March of the year it joined.
            if year == joinYear && month < 3 {
                return YearDay(date: formatter.string(from: date), count: 0, level: 0)
            }
            var chance = (weekday == 1 || weekday == 7 ? 0.22 : 0.55) + growth
            if month == 3 || month == 4 { chance += 0.2 }
            if month == 8 { chance -= 0.25 }
            let active = ContributionSnapshot.noise(seed) < chance
            let level = active ? [1, 1, 1, 2, 2, 2, 3, 3, 4][Int(ContributionSnapshot.noise(seed &* 31 &+ 7) * 9)] : 0
            return YearDay(
                date: formatter.string(from: date),
                count: ContributionSnapshot.sampleCount(level: level, seed: seed),
                level: level
            )
        }
        return ContributionYear(year: year, days: days)
    }
}
