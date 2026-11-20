import Foundation

extension ContributionSnapshot {
    /// A believable year ending today: busy weekdays, lighter weekends, a quiet
    /// stretch in the middle and a live streak at the end. Deterministic, so
    /// previews don't reshuffle between renders.
    ///
    /// Stands in wherever real data can't: the widget gallery before anyone
    /// has connected, the in-app style previews, and demo screenshots.
    ///
    /// `quiet` leaves that many days empty at the end, today included: 1 for
    /// a streak that's waiting on today, 2 for one that ended yesterday.
    ///
    /// Demo mode adds the rest of a real habit: `restWeekday` (0 is Sunday)
    /// left empty inside the streak for rest days, `freezeDaysAgo` for one
    /// missed day the freeze covers, and `bestRun`, an older run of that many
    /// days ending `bestRunEndsDaysAgo` days back, so the best streak beats
    /// the current one.
    static func sample(
        streak: Int = 12,
        quiet: Int = 0,
        restWeekday: Int? = nil,
        freezeDaysAgo: Int? = nil,
        bestRun: Int? = nil,
        bestRunEndsDaysAgo: Int = 150,
        asOf now: Date = Date()
    ) -> ContributionSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: now) // Sunday = 1
        // 52 full weeks plus this week so far, the same shape `from(_:)` keeps.
        let dayCount = 52 * 7 + (weekday == 7 ? 0 : weekday)

        var levels: [Int] = []
        var counts: [Int] = []
        for index in 0..<dayCount {
            let daysAgo = dayCount - 1 - index
            let dayOfWeek = ((weekday - 1 - daysAgo) % 7 + 7) % 7 // 0 = Sunday
            let active: Bool
            if daysAgo < quiet {
                active = false
            } else if daysAgo < quiet + streak {
                // Inside the streak: busy, apart from rest days and the freeze.
                active = dayOfWeek != restWeekday && daysAgo != freezeDaysAgo.map { $0 + quiet }
            } else if daysAgo == quiet + streak || (140...150).contains(daysAgo) {
                active = false // the break before this streak, and a holiday
            } else if let bestRun, (bestRunEndsDaysAgo..<bestRunEndsDaysAgo + bestRun).contains(daysAgo) {
                active = true
            } else if let bestRun, daysAgo == bestRunEndsDaysAgo + bestRun || daysAgo == bestRunEndsDaysAgo - 1 {
                active = false // the days either side of the best run
            } else {
                let isWeekend = dayOfWeek == 0 || dayOfWeek == 6
                active = noise(daysAgo) < (isWeekend ? 0.25 : 0.72)
            }

            // Weighted toward the lighter greens, like most real graphs.
            let level = active ? [1, 1, 1, 2, 2, 2, 3, 3, 4][Int(noise(daysAgo &* 31 &+ 7) * 9)] : 0
            levels.append(level)
            counts.append(sampleCount(level: level, seed: daysAgo))
        }

        return ContributionSnapshot(
            totalContributions: counts.reduce(0, +),
            recentLevels: levels,
            lastDate: ContributionCalendar.dateFormatter.string(from: now),
            fetchedAt: now,
            lastDayCount: counts.last,
            recentCounts: counts
        )
    }

    /// A day's contributions that GitHub would shade at `level`.
    static func sampleCount(level: Int, seed: Int) -> Int {
        let bands = [0...0, 1...3, 4...6, 7...9, 10...14]
        let band = bands[min(max(level, 0), 4)]
        return band.lowerBound + Int(noise(seed &* 17 &+ 3) * Double(band.count))
    }

    /// A stable value in 0..<1 for each seed (SplitMix64).
    static func noise(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}
