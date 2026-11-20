import SwiftUI
import WidgetKit

/// Days drawn the way a theme draws them, wherever they're placed. A whole
/// graph is two canvases and a ring rather than hundreds of views, which
/// keeps it cheap enough for a widget:
///
/// - the quiet layer: empty days, days off, missed days and Marks symbols;
/// - the active layer: pushed days, marked accentable so a tinted home
///   screen paints them in its tint and leaves the rest neutral;
/// - today's ring, a plain shape on top of everything.
///
/// Each canvas reaches a little past the grid, so a glow at the edge is
/// never cut off, and the ring is free to hang outside it.
struct DayGrid: View {
    @Environment(\.dayOffMark) private var mark

    enum Content: Equatable {
        case day(StreakDay)
        /// Before the history starts: an empty cell.
        case blank
        /// Still to come this week: a faint dashed outline.
        case upcoming
    }

    struct Cell: Equatable {
        var content: Content
        var frame: CGRect
        /// After today, which only happens when GitHub's date runs ahead of
        /// the phone's. Not missed yet.
        var afterToday = false
    }

    let cells: [Cell]
    let size: CGSize
    let theme: WidgetTheme
    /// The cell ringed as today.
    var today: Int? = nil

    /// Room past the edges for the glow around the busiest days.
    static let bleed: CGFloat = 10

    var body: some View {
        let painter = DayPainter(theme: theme, mark: mark)
        let cells = cells
        let today = today
        ZStack(alignment: .topLeading) {
            layer { painter.paintQuiet(cells, today: today, in: &$0) }
            layer { painter.paintActive(cells, in: &$0) }
                .widgetAccentable()
            if let today, cells.indices.contains(today) {
                FixedPath(path: painter.ring(around: cells[today].frame))
                    .stroke(theme.todayRing, lineWidth: DayPainter.ringWidth)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func layer(_ draw: @escaping (inout GraphicsContext) -> Void) -> some View {
        let bleed = Self.bleed
        return Canvas { context, _ in
            context.translateBy(x: bleed, y: bleed)
            draw(&context)
        }
        .frame(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        .padding(-bleed)
    }
}

/// A path drawn where it was made, whatever frame it's given.
private struct FixedPath: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}

extension GraphBand {
    /// The band's days placed on its grid, week by week from the left.
    func cells(_ fit: GridFit) -> [DayGrid.Cell] {
        days.enumerated().map { index, day in
            DayGrid.Cell(
                content: day.map { .day($0) } ?? .blank,
                frame: fit.frame(index: index),
                afterToday: isAfterToday(index)
            )
        }
    }
}

/// Equal squares in one row, filling a width: the gaps stretch so the last
/// square meets the right-hand edge.
struct RowFit: Equatable {
    var cell: CGFloat
    var gap: CGFloat
    var count: Int

    init(width: CGFloat, count: Int, gap: CGFloat, maxCell: CGFloat = .greatestFiniteMagnitude) {
        let count = max(count, 1)
        let widest = (width - CGFloat(count - 1) * gap) / CGFloat(count)
        cell = max(floor(min(widest, maxCell)), 1)
        self.gap = count > 1 ? (width - CGFloat(count) * cell) / CGFloat(count - 1) : 0
        self.count = count
    }

    var size: CGSize { CGSize(width: CGFloat(count) * cell + CGFloat(count - 1) * gap, height: cell) }

    func frame(_ index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * (cell + gap), y: 0, width: cell, height: cell)
    }
}

/// Draws days into a canvas. Squares follow the theme's palette, shape and
/// day-off mark; Marks draws one symbol per day in the theme's ink.
struct DayPainter {
    let theme: WidgetTheme
    let mark: DayOffMark

    private func shape(_ rect: CGRect) -> Path {
        CellShape(theme).path(in: rect)
    }

    // MARK: Quiet layer

    func paintQuiet(_ cells: [DayGrid.Cell], today: Int?, in context: inout GraphicsContext) {
        switch theme.cellMode {
        case .squares:
            for cell in cells { paintQuietSquare(cell, in: &context) }
        case .marks:
            paintQuietMarks(cells, today: today, in: &context)
        }
    }

    private func paintQuietSquare(_ cell: DayGrid.Cell, in context: inout GraphicsContext) {
        let rect = cell.frame
        switch cell.content {
        case .blank:
            paintEmpty(rect, in: &context)
        case .upcoming:
            paintUpcoming(rect, in: &context)
        case .day(let day):
            if let off = day.off {
                paintDayOff(off == .freeze ? theme.freeze : theme.dayOff, rect, in: &context)
            } else if day.endedStreak, let missed = theme.missed {
                // Outlined rather than filled, so a red miss can't be
                // mistaken for a busy day in a warm palette.
                paintEmpty(rect, in: &context)
                context.fill(CellOutline(theme, thickness: 0.17).path(in: rect), with: .color(missed), style: FillStyle(eoFill: true))
            } else if !day.isActive {
                paintEmpty(rect, in: &context)
            }
        }
    }

    private func paintEmpty(_ rect: CGRect, in context: inout GraphicsContext) {
        if theme.outlinesEmpty {
            context.fill(CellOutline(theme).path(in: rect), with: .color(theme.color(for: 0)), style: FillStyle(eoFill: true))
        } else {
            context.fill(shape(rect), with: .color(theme.color(for: 0)))
        }
    }

    private func paintUpcoming(_ rect: CGRect, in context: inout GraphicsContext) {
        context.stroke(
            shape(rect.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(theme.color(for: 0)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 2])
        )
    }

    /// A rest day or a freeze, marked the way days off are set to look.
    private func paintDayOff(_ color: Color, _ rect: CGRect, in context: inout GraphicsContext) {
        switch mark {
        case .ring:
            context.fill(CellOutline(theme, dotted: true).path(in: rect), with: .color(color), style: FillStyle(eoFill: true))
        case .dot:
            paintEmpty(rect, in: &context)
            context.fill(CenterDot(fraction: 0.44).path(in: rect), with: .color(color))
        case .stripes:
            let cell = shape(rect)
            context.fill(cell, with: .color(color.opacity(0.22)))
            context.drawLayer { layer in
                layer.clip(to: cell)
                layer.fill(Stripes().path(in: rect), with: .color(color))
            }
        }
    }

    private func paintQuietMarks(_ cells: [DayGrid.Cell], today: Int?, in context: inout GraphicsContext) {
        guard let side = cells.first?.frame.width else { return }

        // Every cell gets the faint square behind its symbol first.
        var background = Path()
        for cell in cells where cell.content != .upcoming {
            background.addPath(shape(cell.frame))
        }
        context.fill(background, with: .color(theme.color(for: 0)))

        let ink = theme.markInk
        let font = Font.system(size: Self.letterSize(side), weight: .bold, design: theme.fontDesign)
        var freeze = context.resolve(Text("F").font(font))
        freeze.shading = .color(ink.opacity(MarkOpacity.freeze))
        var rest = context.resolve(Text("R").font(font))
        rest.shading = .color(ink.opacity(MarkOpacity.rest))

        var crosses = Path()
        var endings = Path()
        for (index, cell) in cells.enumerated() {
            let rect = cell.frame
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let day: StreakDay?
            switch cell.content {
            case .upcoming:
                paintUpcoming(rect, in: &context)
                continue
            case .blank:
                day = nil
            case .day(let shown):
                day = shown
            }
            switch DayMark(day, isToday: index == today, isAfterToday: cell.afterToday) {
            case .freeze:
                context.draw(freeze, at: center, anchor: .center)
            case .rest:
                context.draw(rest, at: center, anchor: .center)
            case .missed(let endedStreak):
                if endedStreak && theme.missed != nil {
                    endings.addPath(Self.cross(in: rect))
                } else {
                    crosses.addPath(Self.cross(in: rect))
                }
            case .dot, .open, .blank:
                break
            }
        }
        let line = StrokeStyle(lineWidth: Self.crossWeight(side), lineCap: .round)
        context.stroke(crosses, with: .color(ink.opacity(MarkOpacity.missed)), style: line)
        if let missed = theme.missed, !endings.isEmpty {
            context.stroke(endings, with: .color(missed), style: line)
        }
    }

    // MARK: Active layer

    func paintActive(_ cells: [DayGrid.Cell], in context: inout GraphicsContext) {
        switch theme.cellMode {
        case .squares: paintActiveSquares(cells, in: &context)
        case .marks: paintDots(cells, in: &context)
        }
    }

    private func paintActiveSquares(_ cells: [DayGrid.Cell], in context: inout GraphicsContext) {
        var glowing = Path()
        var glowSide: CGFloat = 0
        for cell in cells {
            guard case .day(let day) = cell.content, day.isActive, day.off == nil else { continue }
            if theme.glowColor != nil && day.level >= 4 {
                glowing.addPath(shape(cell.frame))
                glowSide = cell.frame.width
            } else {
                context.fill(shape(cell.frame), with: .color(theme.color(for: day.level)))
            }
        }
        guard let glow = theme.glowColor, !glowing.isEmpty else { return }
        // The busiest days glow in their own color, the way a CSS box
        // shadow of 0.7 of a cell spreads around them.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: glow, radius: glowSide * 0.35))
            layer.fill(glowing, with: .color(theme.color(for: 4)))
        }
    }

    private func paintDots(_ cells: [DayGrid.Cell], in context: inout GraphicsContext) {
        var byLevel = [Path](repeating: Path(), count: 5)
        for cell in cells {
            guard case .day(let day) = cell.content, day.isActive, !cell.afterToday else { continue }
            let rect = cell.frame
            let size = (rect.width * 0.46).rounded()
            byLevel[min(day.level, 4)].addEllipse(in: CGRect(
                x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size
            ))
        }
        for level in 1...4 where !byLevel[level].isEmpty {
            context.fill(byLevel[level], with: .color(theme.markInk.opacity(MarkOpacity.dot[level])))
        }
    }

    // MARK: Today

    static let ringWidth: CGFloat = 1.5

    /// The center line of the thin ring around today: 1.5pt clear of the
    /// square, following its corners the way a CSS outline does.
    func ring(around rect: CGRect) -> Path {
        let outset = 1.5 + Self.ringWidth / 2
        let ring = rect.insetBy(dx: -outset, dy: -outset)
        let corner = theme.form == .box ? theme.cornerRadius(for: rect.width) : rect.width * 0.25
        if corner >= rect.width / 2 {
            return Path(ellipseIn: ring)
        } else if corner == 0 {
            return Path(ring)
        }
        return Path(roundedRect: ring, cornerRadius: corner + outset)
    }

    // MARK: Symbol sizes

    /// F and R: bold, 0.72 of the cell.
    static func letterSize(_ side: CGFloat) -> CGFloat {
        max((side * 0.72).rounded(), 4)
    }

    private static func crossSize(_ side: CGFloat) -> CGFloat {
        (side * 0.9).rounded()
    }

    static func crossWeight(_ side: CGFloat) -> CGFloat {
        max(crossSize(side) * 0.09, 0.8)
    }

    /// The × of a missed day, the size of a bold × at 0.9 of the cell.
    static func cross(in rect: CGRect) -> Path {
        let arm = crossSize(rect.width) * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - arm, y: rect.midY - arm))
        path.addLine(to: CGPoint(x: rect.midX + arm, y: rect.midY + arm))
        path.move(to: CGPoint(x: rect.midX + arm, y: rect.midY - arm))
        path.addLine(to: CGPoint(x: rect.midX - arm, y: rect.midY + arm))
        return path
    }
}

/// One row of weeks with, on Large, month names above it and Mon, Wed, Fri
/// down the left.
struct GraphBandView: View {
    let band: GraphBand
    let fit: GridFit
    var labels = false
    let theme: WidgetTheme

    private static let dayNames = ["", "Mon", "", "Wed", "", "Fri", ""]

    var body: some View {
        VStack(alignment: .leading, spacing: GraphLayout.monthGap) {
            if labels {
                monthRow
                    .padding(.leading, GraphLayout.dayColumn + GraphLayout.dayGap)
            }
            HStack(alignment: .top, spacing: GraphLayout.dayGap) {
                if labels { dayColumn }
                DayGrid(cells: band.cells(fit), size: fit.size, theme: theme, today: band.today)
            }
        }
    }

    private var labelFont: Font {
        .system(size: 10, weight: .semibold, design: theme.fontDesign)
    }

    private var monthRow: some View {
        ZStack(alignment: .topLeading) {
            ForEach(band.monthLabels(), id: \.week) { label in
                Text(label.text)
                    .font(labelFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize()
                    .offset(x: CGFloat(label.week) * fit.columnStep)
            }
        }
        .frame(width: fit.width, height: GraphLayout.monthRow, alignment: .topLeading)
    }

    private var dayColumn: some View {
        VStack(alignment: .leading, spacing: fit.rowGap) {
            ForEach(0..<7, id: \.self) { row in
                Text(Self.dayNames[row])
                    .font(labelFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize()
                    .frame(width: GraphLayout.dayColumn, height: fit.cell, alignment: .leading)
            }
        }
    }
}
