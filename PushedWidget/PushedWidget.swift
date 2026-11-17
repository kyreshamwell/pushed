import SwiftUI
import WidgetKit

struct PushedWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetContentMargins) var margins
    let entry: StreakEntry

    var body: some View {
        PushedWidgetView(
            snapshot: entry.snapshot,
            family: family,
            style: entry.style,
            layout: entry.layout,
            stat: entry.stat,
            custom: entry.custom,
            protection: entry.protection,
            now: entry.date,
            margins: margins
        )
    }
}

struct PushedWidget: Widget {
    let kind = "PushedWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetOptionsIntent.self, provider: Provider()) { entry in
            PushedWidgetEntryView(entry: entry)
                .modifier(StyleContainerBackground(style: entry.style, custom: entry.custom))
        }
        .configurationDisplayName("Contribution Graph")
        .description("Your GitHub contribution graph and commit streak, in six styles, your own designs, or a different one each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // PushedWidgetView applies the standard margins itself, so its
        // squares can be sized to meet them exactly.
        .contentMarginsDisabled()
    }
}

/// Every style paints its own backdrop. Classic's follows light and dark
/// mode: GitHub's #0D1117 in the dark and white in the light.
private struct StyleContainerBackground: ViewModifier {
    let style: WidgetStyle
    let custom: CustomWidgetStyle

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { WidgetBackground(style: style, custom: custom) }
    }
}

@main
struct PushedWidgetBundle: WidgetBundle {
    var body: some Widget {
        PushedWidget()
        PushedLockWidget()
    }
}

// One preview per style, so each look can be tuned in Xcode's canvas without
// touching the home screen.
#Preview("Classic", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .classic, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .classic, layout: .streak)
}

#Preview("Aurora", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .aurora, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .aurora, layout: .streak)
}

#Preview("Ember", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .ember, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .ember, layout: .streak)
}

#Preview("Terminal", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .terminal, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .terminal, layout: .streak)
}

#Preview("Paper", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .paper, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .paper, layout: .streak)
}

#Preview("Marks", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .marks, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .marks, layout: .streak)
}

#Preview("Custom", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .custom, layout: .graph, custom: .default)
    StreakEntry(date: .now, snapshot: .sample(), style: .custom, layout: .streak, custom: .default)
}
