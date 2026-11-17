import SwiftUI
import WidgetKit

/// Choosing the weekly rest days.
struct RestDaysView: View {
    @State private var protection: StreakProtection
    private let apply: (StreakProtection) -> Void

    init(protection: StreakProtection, apply: @escaping (StreakProtection) -> Void) {
        _protection = State(initialValue: protection)
        self.apply = apply
    }

    private var chosen: Set<Int> { protection.chosenWeekdays }

    var body: some View {
        Form {
            Section {
                ForEach(Weekday.all, id: \.self) { weekday in
                    let isOn = chosen.contains(weekday)
                    // With two chosen, one has to come off before another goes on.
                    let isLocked = !isOn && chosen.count >= StreakProtection.maxRestDays
                    Button {
                        toggle(weekday)
                    } label: {
                        HStack {
                            Text(Weekday.name(weekday))
                                // Inside a button, .primary means the tint.
                                .foregroundStyle(isLocked ? Color.secondary : Color.primary)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(isLocked)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            } header: {
                Text("Rest days")
            } footer: {
                Text(scheduleNote)
            }

        }
        .navigationTitle("Rest Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ weekday: Int) {
        var weekdays = chosen
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        protection.setWeekdays(weekdays, asOf: Date())
        apply(protection)
    }

    /// Says when a change takes effect, since swapping rest days waits for
    /// the next week.
    private var scheduleNote: String {
        let limit = "Up to two a week. The streak steps over them."
        if TestScenario.current != .off {
            return "\(limit) While testing, changes apply at once."
        }
        guard let start = protection.pendingStart(asOf: Date()) else { return limit }
        let startText = start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(limit) This change starts \(startText)."
    }
}

/// Calendar weekdays, 1 for Sunday through 7 for Saturday.
enum Weekday {
    static let all = Array(1...7)

    /// A calendar made from an identifier alone has no locale, and hands
    /// back short names for both lists.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }()

    static func name(_ weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    /// "Sat, Sun": in week order, except that a Sunday paired with a Saturday
    /// goes last, the way a weekend is said.
    static func shortNames(_ weekdays: Set<Int>) -> String {
        let symbols = calendar.shortWeekdaySymbols
        var ordered = weekdays.sorted()
        if ordered == [1, 7] { ordered = [7, 1] }
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
