import SwiftUI
import WidgetKit

/// The Lock Screen draws everything in one tint, so these lean on shape and
/// weight rather than color: a ring that closes once you've pushed, and the
/// same day-off mark as on the home screen.
///
/// Lives in Shared rather than the extension so it can be drawn outside a
/// widget too, the way the home-screen view is.
struct LockScreenView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    var protection: StreakProtection = AppConfig.streakProtection
    var now = Date()
    var icon: String = AppConfig.streakIcon
    var dayOffMark: DayOffMark = AppConfig.dayOffMark

    var body: some View {
        content.environment(\.dayOffMark, dayOffMark)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            let history = snapshot.history(protection: protection, asOf: now)
            switch family {
            case .accessoryCircular: circular(history)
            case .accessoryRectangular: rectangular(history)
            default: inline(history)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Set up Pushed")
            default:
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title3)
                    .accessibilityLabel("Open Pushed to connect your GitHub")
            }
        }
    }

    private func circular(_ history: StreakHistory) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            TodayRing(today: history.today)
                .padding(3)
            VStack(spacing: -1) {
                Text("\(history.streak)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(history.streak == 1 ? "day" : "days")
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .opacity(0.8)
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(history.streak) day streak. \(history.today.spokenStatus)")
    }

    private func rectangular(_ history: StreakHistory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(icon == StreakIcon.none ? "\(history.streak)-day streak" : "\(icon) \(history.streak)-day streak")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Text(history.today.caption)
                .font(.caption)
                .lineLimit(1)
                .opacity(0.85)
            WeekStrip(
                days: history.days(last: 7),
                today: history.today,
                theme: .lockScreen(renderingMode)
            )
            .frame(height: 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(history.streak) day streak. \(history.today.spokenStatus)")
    }

    /// One line above the clock: an image and some text is all it holds.
    private func inline(_ history: StreakHistory) -> some View {
        let status: String = switch history.today {
        case .pushed: "pushed"
        case .off(.rest): "rest day"
        case .off(.freeze): "frozen"
        case .pending: "not yet"
        }
        return Label("\(history.streak) day\(history.streak == 1 ? "" : "s") · \(status)", systemImage: "flame.fill")
    }
}

/// Closed once today's push is in. Faint while it's still owed, and dashed on
/// a day off, when nothing is.
private struct TodayRing: View {
    let today: StreakHistory.Today

    var body: some View {
        switch today {
        case .pushed:
            Circle().strokeBorder(lineWidth: 3).widgetAccentable()
        case .off:
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        case .pending:
            Circle().strokeBorder(lineWidth: 3).opacity(0.25)
        }
    }
}

extension WidgetTheme {
    /// The Lock Screen's week strip keeps the look it shipped with: Classic
    /// as it was before the 1.3 redesign. The home screen looks can change
    /// freely without moving anything here.
    static func lockScreen(_ renderingMode: WidgetRenderingMode) -> WidgetTheme {
        guard renderingMode == .fullColor else {
            return WidgetTheme(
                levels: [0.18, 0.4, 0.62, 0.82, 1].map { Color.white.opacity($0) },
                primaryText: .primary,
                secondaryText: .secondary,
                numberFill: AnyShapeStyle(Color.primary),
                pushed: .primary,
                pending: .primary,
                cornerFraction: 0.25,
                glows: false,
                fontDesign: .default,
                isMonochrome: true,
                freeze: Color.white.opacity(0.62)
            )
        }
        return WidgetTheme(
            levels: [
                Color(red: 0.184, green: 0.212, blue: 0.247),
                Color(red: 0.055, green: 0.267, blue: 0.161),
                Color(red: 0.000, green: 0.427, blue: 0.196),
                Color(red: 0.149, green: 0.651, blue: 0.255),
                Color(red: 0.224, green: 0.827, blue: 0.325),
            ],
            primaryText: .primary,
            secondaryText: .secondary,
            numberFill: AnyShapeStyle(Color.primary),
            pushed: .green,
            pending: .orange,
            cornerFraction: 0.25,
            glows: false,
            fontDesign: .default,
            ringsPending: false
        )
    }
}
