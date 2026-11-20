import SwiftUI
import UIKit
import WidgetKit

extension Color {
    /// The app's tint: the mockups' green, a step deeper in light mode so it
    /// still reads on white.
    static let pushedGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x3F / 255, green: 0xD2 / 255, blue: 0x6A / 255, alpha: 1)
            : UIColor(red: 0x1F / 255, green: 0xA1 / 255, blue: 0x48 / 255, alpha: 1)
    })

    /// Cards on the grouped background: #1C1C1E in dark mode, white in light.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// The page behind the cards: black in dark mode.
    static let page = Color(uiColor: .systemGroupedBackground)
    /// Controls sitting on a card, like a chip or a tile in a sheet.
    static let raised = Color(uiColor: .tertiarySystemFill)
}

/// A press that sinks a little and springs back, like the system's own
/// buttons on cards.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A rounded card on the grouped background.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content.background(Color.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = 18) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// A look in miniature: its backdrop with one of its busiest squares.
struct LookSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let look: WidgetLook
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 9

    var body: some View {
        let theme = look.style.theme(for: colorScheme, custom: look.custom)
        WidgetBackground(style: look.style, custom: look.custom)
            .overlay {
                CellShape(theme)
                    .fill(theme.cellMode == .marks ? theme.markInk : theme.color(for: 4))
                    .frame(width: size * 0.4, height: size * 0.4)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // A hairline, so a light look still has an edge on a light card.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .environment(\.colorScheme, look.style.pinnedColorScheme(custom: look.custom) ?? colorScheme)
            .accessibilityHidden(true)
    }
}

/// The real widget, drawn at its home screen size and then scaled, so text
/// and squares keep the exact proportions they have on the home screen.
struct ScaledWidget: View {
    let look: WidgetLook
    let family: WidgetFamily
    let scale: CGFloat
    let data: PreviewData

    var body: some View {
        let size = WidgetPreviewCard.size(for: family)
        WidgetPreviewCard(
            snapshot: data.snapshot,
            family: family,
            style: look.style,
            layout: .graph,
            icon: data.icon,
            custom: look.custom,
            protection: data.protection,
            dayOffMark: data.dayOffMark,
            now: data.now
        )
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
    }
}

/// Everything a preview draws besides the look: the graph and the extras
/// shown around it.
struct PreviewData: Equatable {
    var snapshot: ContributionSnapshot
    var protection: StreakProtection
    var icon: String
    var dayOffMark: DayOffMark
    var now: Date

    static func == (lhs: PreviewData, rhs: PreviewData) -> Bool {
        lhs.snapshot.fetchedAt == rhs.snapshot.fetchedAt
            && lhs.snapshot.lastDate == rhs.snapshot.lastDate
            && lhs.snapshot.recentLevels == rhs.snapshot.recentLevels
            && lhs.protection == rhs.protection
            && lhs.icon == rhs.icon
            && lhs.dayOffMark == rhs.dayOffMark
            && Calendar.current.isDate(lhs.now, inSameDayAs: rhs.now)
    }
}

/// Names the back button on screens pushed from this one. Home hides its
/// bar, so without this the back button is a bare chevron.
struct BackButtonTitle: UIViewControllerRepresentable {
    let title: String

    func makeUIViewController(context: Context) -> Controller {
        Controller(backTitle: title)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.backTitle = title
        controller.apply()
    }

    final class Controller: UIViewController {
        var backTitle: String

        init(backTitle: String) {
            self.backTitle = backTitle
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        /// The screen this sits in is whichever of the stack's controllers
        /// it's nested inside.
        func apply() {
            guard let stack = navigationController?.viewControllers else { return }
            var current: UIViewController? = self
            while let candidate = current, !stack.contains(candidate) {
                current = candidate.parent
            }
            guard let screen = current else { return }
            screen.navigationItem.backButtonDisplayMode = .default
            screen.navigationItem.backButtonTitle = backTitle
        }
    }
}
