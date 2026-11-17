import SwiftUI
import UIKit
import WidgetKit

/// A complete look for the widget: palette, backdrop, cell shape and type.
/// Picked per widget from Edit Widget, so two widgets can wear different
/// styles side by side. Every look shares one layout, so switching between
/// them changes color, shape and type and never moves anything.
enum WidgetStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic, aurora, ember, terminal, paper
    /// One solid color with a symbol for every day: a dot when pushed, ×
    /// when missed, F for a freeze and R for a rest day.
    case marks
    /// Designed in the app. See `CustomWidgetStyle` and `StyleLibrary`.
    case custom
    /// Not a look of its own: a different saved style each day. It's only
    /// ever a choice in Edit Widget, and `StyleLibrary.look` turns it into
    /// that day's real style before anything is drawn.
    case rotation

    var id: String { rawValue }

    /// The styles that ship with the app.
    static let builtIn: [WidgetStyle] = [.classic, .aurora, .ember, .terminal, .paper, .marks]
    /// Every style that can actually be drawn.
    static let designs: [WidgetStyle] = builtIn + [.custom]

    var name: String {
        switch self {
        case .classic: "Classic"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .terminal: "Terminal"
        case .paper: "Paper"
        case .marks: "Marks"
        case .custom: "Custom"
        case .rotation: "Daily Rotation"
        }
    }

    var tagline: String {
        switch self {
        case .classic: "GitHub's own graph and greens. Follows light and dark mode."
        case .aurora: "Deep navy with teal and violet light. Busy days glow."
        case .ember: "Warm black, coal to flame. Busy days glow like embers."
        case .terminal: "Phosphor green in monospace, with faint scanlines."
        case .paper: "Ink dots on warm paper, with a serif number."
        case .marks: "One color and a symbol for every day."
        case .custom: "Your colors, shape and type."
        case .rotation: "One of your styles, a different one each day."
        }
    }

    /// Styles with their own backdrop pin a scheme, so anything inside that
    /// still uses a system color resolves against that backdrop rather than
    /// the phone's light or dark setting.
    func pinnedColorScheme(custom: CustomWidgetStyle = .default) -> ColorScheme? {
        switch self {
        case .classic, .rotation: nil
        case .paper: .light
        case .aurora, .ember, .terminal, .marks: .dark
        case .custom: custom.colorScheme
        }
    }
}

/// What the widget leads with.
enum WidgetLayout: String, CaseIterable, Identifiable, Sendable {
    /// The contribution graph filling the widget, under a slim header.
    case graph
    /// The streak number, big, with a smaller graph alongside.
    case streak
    /// This week, Sunday to Saturday, in big squares with the day letters.
    case week

    var id: String { rawValue }

    var name: String {
        switch self {
        case .graph: "Graph"
        case .streak: "Big streak"
        case .week: "This week"
        }
    }
}

/// The number a widget leads with.
enum WidgetStat: String, CaseIterable, Identifiable, Sendable {
    case streak
    /// The longest run in the past year.
    case best
    /// Days pushed since Sunday.
    case week
    /// Contributions so far this year, as GitHub counts them.
    case year

    var id: String { rawValue }

    var name: String {
        switch self {
        case .streak: "Current streak"
        case .best: "Best streak"
        case .week: "This week"
        case .year: "This year"
        }
    }
}

/// How each day is drawn.
enum CellMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A square shaded by how busy the day was.
    case squares
    /// A symbol for what happened: a dot when pushed (brighter when busier),
    /// × for a missed day, F for a freeze and R for a rest day.
    case marks

    var id: String { rawValue }

    var name: String {
        switch self {
        case .squares: "Squares"
        case .marks: "Marks"
        }
    }
}

/// The resolved colors and shapes a style draws with.
struct WidgetTheme {
    /// Level 0 (no contributions) through 4. In Marks, level 0 is the cell
    /// behind each symbol and the others are the dot at each level.
    var levels: [Color]
    var primaryText: Color
    var secondaryText: Color
    var numberFill: AnyShapeStyle
    /// The look's accent: it fills the check circle and the status dot once
    /// you've pushed today.
    var pushed: Color
    /// The empty ring they turn into while today's push is still owed.
    var pending: Color
    /// Corner radius as a fraction of the cell: 0 is a square, 0.5 a dot.
    var cornerFraction: CGFloat
    /// The smallest corner radius, in points, so tiny cells still read as
    /// softened rather than sharp.
    var minimumCorner: CGFloat = 0
    /// A soft halo around the busiest days.
    var glows: Bool
    var fontDesign: Font.Design
    /// The streak number's typeface when it differs from the rest, like
    /// Paper's serif. Nil uses `fontDesign`.
    var numberDesign: Font.Design? = nil
    var isMonochrome = false
    /// "Not pushed yet" is an empty ring in every look: the dot or circle
    /// empties and nothing else moves.
    var ringsPending = true
    /// Draw empty days as a hollow outline instead of a filled square.
    var outlinesEmpty = false
    /// How far apart the squares sit, as a multiple of the usual gap.
    var spacing: CGFloat = 1
    /// Leave out labels and captions: the number and the squares only.
    var hidesText = false
    /// The outline each day is drawn in; boxes use `cornerFraction`.
    var form: CellForm = .box
    var fontWidth: Font.Width = .standard
    var numberWeight: Font.Weight = .bold
    /// A freeze is marked in ice blue, so it reads apart from a rest day.
    var freeze = Color(hex: 0x7DD3FC)
    /// The day a streak ended on. Nil draws it like any other empty day.
    var missed: Color? = nil
    var cellMode: CellMode = .squares
    /// The one color Marks draws its symbols in. Nil uses the text color.
    var ink: Color? = nil

    func color(for level: Int) -> Color {
        levels[min(max(level, 0), levels.count - 1)]
    }

    /// The color of a rest day's mark. It borrows a mid level,
    /// so a day off sits in the same family as the days around it without
    /// being as loud as a day that was pushed.
    var dayOff: Color { color(for: 2) }

    /// The thin ring around today's square.
    var todayRing: Color { primaryText }

    /// What the symbols in Marks are drawn in.
    var markInk: Color { ink ?? primaryText }

    /// The halo around the busiest days, in the busiest level's color.
    var glowColor: Color? { glows ? color(for: 4) : nil }

    var numberFontDesign: Font.Design { numberDesign ?? fontDesign }

    /// The corner radius of a cell this size, in points.
    func cornerRadius(for side: CGFloat) -> CGFloat {
        CellShape.radius(side: side, cornerFraction: cornerFraction, minimumCorner: minimumCorner)
    }

    /// Tinted and clear home screens drop the backdrop and repaint every pixel
    /// in a single tint, keeping only its alpha, so hue can't tell the levels
    /// apart there. White at stepped opacity still can. Shape and type stay.
    var monochrome: WidgetTheme {
        var theme = WidgetTheme(
            levels: [0.18, 0.4, 0.62, 0.82, 1].map { Color.white.opacity($0) },
            primaryText: .primary,
            secondaryText: .secondary,
            numberFill: AnyShapeStyle(Color.primary),
            pushed: .primary,
            pending: .secondary,
            cornerFraction: cornerFraction,
            minimumCorner: minimumCorner,
            glows: false,
            fontDesign: fontDesign,
            numberDesign: numberDesign,
            isMonochrome: true,
            spacing: spacing,
            hidesText: hidesText,
            form: form,
            fontWidth: fontWidth,
            numberWeight: numberWeight,
            // One tint is all there is here, so a freeze is told apart by
            // nothing but its mark.
            freeze: Color.white.opacity(0.62),
            cellMode: cellMode,
            ink: .white
        )
        if cellMode == .marks {
            // The cell behind a symbol stays a whisper, as in full color.
            theme.levels[0] = Color.white.opacity(0.1)
        }
        return theme
    }
}

/// How bright each of the Marks symbols is, as a share of the ink.
enum MarkOpacity {
    /// A pushed day's dot, by level: brighter when busier.
    static let dot: [Double] = [0, 0.55, 0.72, 0.86, 1]
    static let freeze = 0.6
    static let rest = 0.38
    static let missed = 0.32
}

extension WidgetStyle {
    func theme(
        for colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode = .fullColor,
        custom: CustomWidgetStyle = .default
    ) -> WidgetTheme {
        let full = fullColorTheme(for: colorScheme, custom: custom)
        return renderingMode == .fullColor ? full : full.monochrome
    }

    private func fullColorTheme(for colorScheme: ColorScheme, custom: CustomWidgetStyle) -> WidgetTheme {
        switch self {
        // Rotation is resolved to a real style long before this. Should it
        // ever arrive here it draws as Classic, not as a blank widget.
        case .classic, .rotation:
            colorScheme == .dark ? Self.classicDark : Self.classicLight
        case .aurora:
            WidgetTheme(
                levels: [Color.white.opacity(0.08)] + [0x1C4E63, 0x2A8C93, 0x6EE7D8, 0xE4D7FF].map { Color(hex: $0) },
                primaryText: Color(hex: 0xF2F5FF),
                secondaryText: Color(hex: 0xE2E8FF, opacity: 0.66),
                numberFill: AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xA7F3E8), Color(hex: 0xE4D7FF)],
                    startPoint: UnitPoint(x: 0, y: 0.1), endPoint: UnitPoint(x: 1, y: 0.9)
                )),
                pushed: Color(hex: 0x6EE7D8),
                pending: Color(hex: 0xE2E8FF, opacity: 0.66),
                cornerFraction: CellShapeChoice.rounded.cornerFraction,
                glows: true,
                fontDesign: .default
            )
        case .ember:
            WidgetTheme(
                levels: [0x2A1A14, 0x6B2410, 0xB8400E, 0xF2761B, 0xFFC46B].map { Color(hex: $0) },
                primaryText: Color(hex: 0xFFF4E8),
                secondaryText: Color(hex: 0xFDC896, opacity: 0.72),
                // Top to bottom across the digits themselves, not the taller
                // box SwiftUI sets text in, so they run from pale gold to flame.
                numberFill: AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xFFE1A6), Color(hex: 0xF2761B)],
                    startPoint: UnitPoint(x: 0.5, y: 0.12), endPoint: UnitPoint(x: 0.5, y: 0.89)
                )),
                pushed: Color(hex: 0xF2761B),
                pending: Color(hex: 0xFDC896, opacity: 0.72),
                cornerFraction: CellShapeChoice.rounded.cornerFraction,
                glows: true,
                fontDesign: .default
            )
        case .terminal:
            WidgetTheme(
                levels: [0x0E1A12, 0x14532D, 0x15803D, 0x22C55E, 0x86EFAC].map { Color(hex: $0) },
                primaryText: Color(hex: 0x86EFAC),
                secondaryText: Color(hex: 0x4E8F62),
                numberFill: AnyShapeStyle(Color(hex: 0x86EFAC)),
                pushed: Color(hex: 0x22C55E),
                pending: Color(hex: 0x4E8F62),
                cornerFraction: 0,
                glows: false,
                fontDesign: .monospaced
            )
        case .paper:
            WidgetTheme(
                levels: [0xE2DACB, 0xC9BBA2, 0x9A8970, 0x5E5243, 0x24211D].map { Color(hex: $0) },
                primaryText: Color(hex: 0x24211D),
                secondaryText: Color(hex: 0x6E6456),
                numberFill: AnyShapeStyle(Color(hex: 0x24211D)),
                pushed: Color(hex: 0x24211D),
                pending: Color(hex: 0x6E6456),
                cornerFraction: 0.5,
                glows: false,
                fontDesign: .default,
                numberDesign: .serif,
                freeze: Color(hex: 0x0284C7)
            )
        case .marks:
            Self.marksTheme
        case .custom:
            custom.theme
        }
    }

    /// GitHub's own dark graph, on GitHub's own #0D1117.
    private static let classicDark = WidgetTheme(
        levels: [0x161B22, 0x0E4429, 0x006D32, 0x26A641, 0x39D353].map { Color(hex: $0) },
        primaryText: Color(hex: 0xE6EDF3),
        secondaryText: Color(hex: 0x8B949E),
        numberFill: AnyShapeStyle(Color(hex: 0xE6EDF3)),
        pushed: Color(hex: 0x39D353),
        pending: Color(hex: 0x8B949E),
        cornerFraction: CellShapeChoice.soft.cornerFraction,
        minimumCorner: CellShapeChoice.soft.minimumCorner,
        glows: false,
        fontDesign: .default
    )

    /// GitHub's light greens, on white.
    private static let classicLight = WidgetTheme(
        levels: [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39].map { Color(hex: $0) },
        primaryText: Color(hex: 0x1F2328),
        secondaryText: Color(hex: 0x59636E),
        numberFill: AnyShapeStyle(Color(hex: 0x1F2328)),
        pushed: Color(hex: 0x216E39),
        pending: Color(hex: 0x59636E),
        cornerFraction: CellShapeChoice.soft.cornerFraction,
        minimumCorner: CellShapeChoice.soft.minimumCorner,
        glows: false,
        fontDesign: .default,
        freeze: Color(hex: 0x0284C7)
    )

    private static let marksInk = Color(hex: 0xF2F2F2)

    /// One solid ink on near black. The levels are the pushed-day dot at
    /// each brightness; level 0 is the faint cell behind every symbol.
    private static let marksTheme = WidgetTheme(
        levels: [Color.white.opacity(0.045)] + MarkOpacity.dot.dropFirst().map { marksInk.opacity($0) },
        primaryText: marksInk,
        secondaryText: Color(hex: 0x8E8E93),
        numberFill: AnyShapeStyle(marksInk),
        pushed: marksInk,
        pending: Color(hex: 0x8E8E93),
        cornerFraction: CellShapeChoice.soft.cornerFraction,
        minimumCorner: CellShapeChoice.soft.minimumCorner,
        glows: false,
        fontDesign: .default,
        freeze: Color(hex: 0xAEAEB2),
        cellMode: .marks,
        ink: marksInk
    )
}

extension WidgetStyle {
    /// The solid colors a style's squares sit on, used to check every level
    /// stands apart from them. Classic's ground follows light and dark mode
    /// (#0D1117 or white) and Custom's is whatever was picked, so neither is
    /// listed here.
    var backdrop: [UInt32] {
        switch self {
        case .classic, .custom, .rotation: []
        case .aurora: [0x0A0F24]
        case .ember: [0x140B08]
        case .terminal: [0x0B1A10, 0x030604]
        case .paper: [0xF7F2E8, 0xEDE5D6]
        case .marks: [0x111113]
        }
    }
}

/// A style's backdrop: what the widget paints behind everything, and what
/// stands in for it inside the app.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: WidgetStyle
    var custom: CustomWidgetStyle = .default

    var body: some View {
        switch style {
        case .classic, .rotation:
            Color(hex: colorScheme == .dark ? 0x0D1117 : 0xFFFFFF)
        case .aurora:
            ZStack {
                Color(hex: 0x0A0F24)
                EllipseGlow(color: Color(hex: 0x2DD4BF), opacity: 0.30, center: .topLeading, radii: CGSize(width: 0.9, height: 1.2), fade: 0.55)
                EllipseGlow(color: Color(hex: 0xA78BFA), opacity: 0.34, center: .bottomTrailing, radii: CGSize(width: 0.9, height: 1.2), fade: 0.6)
            }
        case .ember:
            ZStack {
                Color(hex: 0x140B08)
                EllipseGlow(color: Color(hex: 0xEA580C), opacity: 0.28, center: .topTrailing, radii: CGSize(width: 0.8, height: 0.9), fade: 0.6)
                EllipseGlow(color: Color(hex: 0xFACC15), opacity: 0.08, center: .bottomLeading, radii: CGSize(width: 0.7, height: 0.7), fade: 0.6)
            }
        case .terminal:
            ZStack {
                EllipseGlow(
                    stops: [.init(color: Color(hex: 0x0B1A10), location: 0), .init(color: Color(hex: 0x030604), location: 1)],
                    center: UnitPoint(x: 0.5, y: 0.4), radii: CGSize(width: 0.9, height: 0.9)
                )
                Scanlines()
            }
        case .paper:
            LinearGradient(
                colors: [Color(hex: 0xF7F2E8), Color(hex: 0xEDE5D6)],
                startPoint: .top, endPoint: .bottom
            )
        case .marks:
            Color(hex: 0x111113)
        case .custom:
            if custom.usesGradient {
                LinearGradient(
                    colors: [custom.background.color, custom.backgroundEnd.color],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                custom.background.color
            }
        }
    }
}

/// An elliptical radial gradient sized like CSS's `radial-gradient(90% 120%
/// at 0% 0%, ...)`: its radii are fractions of the width and the height,
/// which SwiftUI's own elliptical gradient can't set independently. Past
/// the ellipse the last stop carries on.
private struct EllipseGlow: View {
    var stops: [Gradient.Stop]
    var center: UnitPoint
    /// Horizontal and vertical radius, as fractions of the width and height.
    var radii: CGSize

    init(stops: [Gradient.Stop], center: UnitPoint, radii: CGSize) {
        self.stops = stops
        self.center = center
        self.radii = radii
    }

    /// A color fading out to nothing at `fade` of the way to the edge.
    init(color: Color, opacity: Double, center: UnitPoint, radii: CGSize, fade: CGFloat) {
        self.init(
            stops: [.init(color: color.opacity(opacity), location: 0), .init(color: color.opacity(0), location: fade)],
            center: center,
            radii: radii
        )
    }

    var body: some View {
        Canvas { context, size in
            let rx = max(radii.width * size.width, 1)
            let ry = max(radii.height * size.height, 1)
            let origin = CGPoint(x: center.x * size.width, y: center.y * size.height)
            // Squash a circle into the ellipse, then cover the whole view.
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: 1, y: ry / rx)
            let cover = CGRect(
                x: -origin.x, y: -origin.y * rx / ry,
                width: size.width, height: size.height * rx / ry
            )
            context.fill(
                Path(cover),
                with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: rx)
            )
        }
    }
}

/// Faint horizontal lines, like an old CRT.
private struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for y in stride(from: 0, to: size.height, by: 3) {
                lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            }
            context.fill(lines, with: .color(.white.opacity(0.03)))
        }
    }
}

extension View {
    /// A soft halo in `color`, or nothing at all when it's nil. Skipping the
    /// modifier outright keeps the hundreds of quiet cells cheap to draw.
    @ViewBuilder
    func glow(_ color: Color?, radius: CGFloat) -> some View {
        if let color {
            shadow(color: color.opacity(0.75), radius: radius)
        } else {
            self
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
