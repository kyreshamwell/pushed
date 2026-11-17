import Foundation

/// The words on Home, worked out from the data alone so they can be tested.
enum HomeWords {
    /// "Today Aurora · Tomorrow Ember" while looks rotate, "Today Aurora" for
    /// one, and "Classic" when nothing rotates and Home shows Classic.
    static func rotationCaption(
        _ library: StyleLibrary,
        on day: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let looks = library.rotationSchedule(from: day, calendar: calendar).compactMap(library.look(of:))
        switch looks.count {
        case 0: return WidgetStyle.classic.name
        case 1: return "Today \(looks[0].name)"
        default: return "Today \(looks[0].name) · Tomorrow \(looks[1].name)"
        }
    }

    static func stylesSummary(_ library: StyleLibrary) -> String {
        switch library.rotation.count {
        case 0: "Nothing in rotation"
        case 1: "1 look in rotation"
        default: "\(library.rotation.count) looks in rotation"
        }
    }

    enum TodayKind: Equatable {
        case pushed, pending, rest, freeze
    }

    struct Today: Equatable {
        var kind: TodayKind
        var title: String
        var detail: String?
        var symbol: String
    }

    /// Today's card. `count` is today's contributions when they're known;
    /// without it the card says nothing rather than guess.
    static func today(_ history: StreakHistory, count: Int?) -> Today {
        switch history.today {
        case .pushed:
            return Today(
                kind: .pushed,
                title: "Pushed today",
                detail: count.map { "\($0) contribution\($0 == 1 ? "" : "s")" },
                symbol: "checkmark"
            )
        case .pending:
            let streak = history.streak
            let detail = streak > 0 ? "Push by midnight to keep your \(streak)-day streak"
                : history.canSaveStreak ? "Push today to keep it going"
                : "Push today to start a streak"
            return Today(kind: .pending, title: "Not yet today", detail: detail, symbol: "circle.dashed")
        case .off(.rest):
            return Today(kind: .rest, title: "Rest day", detail: "Your streak carries on", symbol: "moon.zzz.fill")
        case .off(.freeze):
            return Today(kind: .freeze, title: "Streak frozen", detail: "Today is covered", symbol: "snowflake")
        }
    }

    /// Today's contributions, when the saved data runs to today and has the
    /// count. Data saved before 1.3 doesn't.
    static func todayCount(_ snapshot: ContributionSnapshot, history: StreakHistory, now: Date = Date()) -> Int? {
        guard history.today == .pushed,
              snapshot.lastDate == ContributionCalendar.dateFormatter.string(from: now),
              let count = snapshot.lastDayCount, count > 0
        else { return nil }
        return count
    }

    /// "just now", or "4 minutes ago".
    static func synced(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
