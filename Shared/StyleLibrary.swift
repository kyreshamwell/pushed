import Foundation

/// A custom style someone designed and kept, under the name they gave it.
struct SavedStyle: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var style: CustomWidgetStyle

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        style: CustomWidgetStyle = .default
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.style = style
    }

    /// A name that's been cleared still needs something to show.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

/// A style ready to draw: one of the built-ins, or a custom design, with the
/// name to show beside it.
struct WidgetLook: Equatable, Sendable {
    var style: WidgetStyle
    var custom: CustomWidgetStyle = .default
    var name: String

    init(_ style: WidgetStyle) {
        self.style = style
        self.name = style.name
    }

    init(_ saved: SavedStyle) {
        style = .custom
        custom = saved.style
        name = saved.displayName
    }
}

/// One look someone can pick: a built-in, or one of their saved styles.
enum LookID: Hashable, Sendable {
    case builtIn(WidgetStyle)
    case saved(UUID)
}

/// Pins which place in the rotation shows on one day. It's moved whenever the
/// rotation changes, so adding a look never changes today's look and taking
/// one away only moves today when it was today's.
struct RotationAnchor: Codable, Equatable, Sendable {
    /// Days since 1 January 2001 in the phone's calendar.
    var day: Int
    /// The place in the rotation shown on that day.
    var index: Int

    /// What every rotation counted from before 1.3: the first look on
    /// 1 January 2001, then one step each midnight.
    static let epoch = RotationAnchor(day: 0, index: 0)
}

/// Every custom style someone has saved, in the order they're shown, and the
/// looks that take turns in the daily rotation.
///
/// Kept in the shared container, so a widget draws exactly what the app
/// previewed. There's always at least one style in it: a widget set to Custom
/// needs something to show.
struct StyleLibrary: Codable, Equatable, Sendable {
    var styles: [SavedStyle]
    /// The looks that take turns, in the order they were added.
    private(set) var rotation: [LookID]
    /// Which of them shows on which day. Nil while nothing rotates.
    private(set) var anchor: RotationAnchor?

    init(styles: [SavedStyle], rotation: [LookID] = [], anchor: RotationAnchor? = nil) {
        self.styles = styles
        self.rotation = rotation
        self.anchor = anchor
        sanitizeRotation()
    }

    /// Enough to play with, short enough that Edit Widget's list stays usable.
    static let maxStyles = 24

    /// The style from before there was a library always gets this id, so the
    /// app and the widget agree on it without either having to write first.
    static let firstStyleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// What everyone starts with: the one custom style there used to be,
    /// carried over as it was. `rotating` puts it in the rotation, which is
    /// what a Daily Rotation widget showed before 1.3 when nothing was checked.
    static func starting(with style: CustomWidgetStyle = .default, rotating: Bool = false) -> StyleLibrary {
        StyleLibrary(
            styles: [SavedStyle(id: firstStyleID, name: "My Style", createdAt: .distantPast, style: style)],
            rotation: rotating ? [.saved(firstStyleID)] : [],
            anchor: rotating ? .epoch : nil
        )
    }
}

// MARK: - Editing

extension StyleLibrary {
    /// Setting a style to nil deletes it, and takes it out of the rotation.
    subscript(id: UUID) -> SavedStyle? {
        get { styles.first { $0.id == id } }
        set {
            guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
            if let newValue {
                styles[index] = newValue
            } else {
                remove(id)
            }
        }
    }

    var canAdd: Bool { styles.count < Self.maxStyles }
    /// The last one stays, so Custom widgets always have a style.
    var canRemove: Bool { styles.count > 1 }

    /// Adds a style and hands it back, or nil when the library is full.
    /// With no design given, it starts from the next of the starter looks.
    @discardableResult
    mutating func add(_ style: CustomWidgetStyle? = nil, named name: String? = nil) -> SavedStyle? {
        guard canAdd else { return nil }
        let starters = CustomWidgetStyle.starters
        let saved = SavedStyle(
            name: unusedName(from: name ?? "Style \(styles.count + 1)"),
            style: style ?? starters[styles.count % starters.count]
        )
        styles.append(saved)
        return saved
    }

    /// A copy placed right after the original, named after it.
    @discardableResult
    mutating func duplicate(_ id: UUID) -> SavedStyle? {
        guard canAdd, let index = styles.firstIndex(where: { $0.id == id }) else { return nil }
        let original = styles[index]
        let copy = SavedStyle(name: unusedName(from: "\(original.displayName) copy"), style: original.style)
        styles.insert(copy, at: index + 1)
        return copy
    }

    /// Deletes a saved style, unless it's the last one, and takes it out of
    /// the rotation the same way the circle on its card would.
    mutating func remove(
        _ id: UUID,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        guard canRemove, let index = styles.firstIndex(where: { $0.id == id }) else { return }
        removeFromRotation(.saved(id), on: day, calendar: calendar)
        styles.remove(at: index)
    }

    /// `name`, or `name 2`, `name 3` and so on until it's one not taken.
    func unusedName(from name: String) -> String {
        let taken = Set(styles.map(\.displayName))
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    /// What a look is called and how it draws, or nil for a saved style
    /// that's gone.
    func look(of id: LookID) -> WidgetLook? {
        switch id {
        case .builtIn(let style): WidgetLook(style)
        case .saved(let saved): self[saved].map(WidgetLook.init)
        }
    }

    /// Whether a look can be drawn and put in the rotation: a real built-in,
    /// or a saved style that's still here.
    func contains(_ id: LookID) -> Bool {
        switch id {
        case .builtIn(let style): WidgetStyle.builtIn.contains(style)
        case .saved(let saved): self[saved] != nil
        }
    }
}

// MARK: - The daily rotation

extension StyleLibrary {
    /// Days since 1 January 2001 in `calendar`, so the count ticks over at
    /// local midnight.
    static func dayNumber(of date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? .distantPast
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
    }

    func isInRotation(_ id: LookID) -> Bool { rotation.contains(id) }
    func isInRotation(_ style: WidgetStyle) -> Bool { isInRotation(.builtIn(style)) }
    func isInRotation(_ id: UUID) -> Bool { isInRotation(.saved(id)) }

    /// The place in the rotation shown on `day`, or nil when nothing rotates.
    func rotationIndex(on day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        let count = rotation.count
        guard count > 0 else { return nil }
        let anchor = anchor ?? .epoch
        let steps = Self.dayNumber(of: day, calendar: calendar) - anchor.day
        return ((anchor.index + steps) % count + count) % count
    }

    /// The look the rotation shows on `day`. It's worked out from the date
    /// and the anchor alone, so the app and every widget land on the same one
    /// without comparing notes, and it moves on by one each midnight. With
    /// nothing in the rotation it's Classic.
    func rotationPick(on day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> WidgetLook {
        guard let index = rotationIndex(on: day, calendar: calendar) else { return WidgetLook(.classic) }
        return look(of: rotation[index]) ?? WidgetLook(.classic)
    }

    /// Every look in the rotation once, in the order they'll show starting
    /// with `day`: the first is that day's, the next is the day after's.
    func rotationSchedule(from day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [LookID] {
        guard let start = rotationIndex(on: day, calendar: calendar) else { return [] }
        return rotation.indices.map { rotation[(start + $0) % rotation.count] }
    }

    /// Puts a look at the end of the rotation. Today keeps its look; the new
    /// one comes round after the ones already there. The first look added
    /// becomes today's.
    mutating func addToRotation(
        _ id: LookID,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        guard contains(id), !isInRotation(id) else { return }
        let today = rotationIndex(on: day, calendar: calendar) ?? 0
        rotation.append(id)
        anchor = RotationAnchor(day: Self.dayNumber(of: day, calendar: calendar), index: today)
    }

    /// Takes a look out of the rotation. If it was today's, today moves on to
    /// the next one in order; otherwise today keeps its look.
    mutating func removeFromRotation(
        _ id: LookID,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        guard let removed = rotation.firstIndex(of: id),
              let today = rotationIndex(on: day, calendar: calendar)
        else { return }
        rotation.remove(at: removed)
        guard !rotation.isEmpty else {
            anchor = nil
            return
        }
        // Earlier looks shift down one place; today's own place is taken by
        // the look after it, wrapping round from the end.
        let index = removed < today ? today - 1 : today % rotation.count
        anchor = RotationAnchor(day: Self.dayNumber(of: day, calendar: calendar), index: index)
    }

    mutating func toggleRotation(
        _ id: LookID,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        if isInRotation(id) {
            removeFromRotation(id, on: day, calendar: calendar)
        } else {
            addToRotation(id, on: day, calendar: calendar)
        }
    }

    mutating func toggleRotation(_ style: WidgetStyle, on day: Date = Date()) {
        toggleRotation(.builtIn(style), on: day)
    }

    mutating func toggleRotation(_ id: UUID, on day: Date = Date()) {
        toggleRotation(.saved(id), on: day)
    }

    /// The looks in the rotation, in the order they were added.
    var rotationLooks: [WidgetLook] { rotation.compactMap(look(of:)) }

    /// Drops looks that can't be drawn (a deleted style, a look this build
    /// doesn't know, a repeat) and keeps the anchor's place in range.
    private mutating func sanitizeRotation() {
        var seen = Set<LookID>()
        rotation = rotation.filter { contains($0) && seen.insert($0).inserted }
        if rotation.isEmpty {
            anchor = nil
        } else if let current = anchor {
            anchor?.index = ((current.index % rotation.count) + rotation.count) % rotation.count
        }
    }
}

// MARK: - What a widget shows

extension StyleLibrary {
    /// What a widget set to `style` draws on `day`. `saved` is the custom
    /// style picked in Edit Widget; a widget from before there was a choice,
    /// or one whose style has since been deleted, gets the first.
    func look(
        for style: WidgetStyle,
        saved: UUID? = nil,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WidgetLook {
        switch style {
        case .rotation:
            return rotationPick(on: day, calendar: calendar)
        case .custom:
            let chosen = saved.flatMap { self[$0] } ?? styles.first
            return chosen.map(WidgetLook.init) ?? WidgetLook(.classic)
        default:
            return WidgetLook(style)
        }
    }
}

// MARK: - Saved data

extension LookID: Codable {
    /// Stored as one string: a built-in look's name, or a saved style's id.
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let id = UUID(uuidString: value) {
            self = .saved(id)
        } else if let style = WidgetStyle(rawValue: value) {
            self = .builtIn(style)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown look \(value)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .builtIn(let style): try container.encode(style.rawValue)
        case .saved(let id): try container.encode(id.uuidString)
        }
    }
}

extension SavedStyle {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, style
    }

    /// Anything missing takes a default, so a style saved by another version
    /// of the app is never thrown away over one field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        style = (try? container.decodeIfPresent(CustomWidgetStyle.self, forKey: .style)) ?? .default
    }
}

extension StyleLibrary {
    private enum CodingKeys: String, CodingKey {
        case styles, rotation, anchor
        /// 1.2 kept the rotation as a flag on each saved style plus this list.
        case rotatingBuiltIns
    }

    /// Just the 1.2 rotation flag of a saved style.
    private struct LegacyFlag: Decodable {
        var inRotation: Bool?
    }

    /// A look this build can't read is skipped rather than failing the list.
    private struct LossyLook: Decodable {
        var id: LookID?
        init(from decoder: Decoder) throws { id = try? LookID(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styles = (try? container.decodeIfPresent([SavedStyle].self, forKey: .styles)) ?? []

        if container.contains(.rotation) {
            rotation = ((try? container.decodeIfPresent([LossyLook].self, forKey: .rotation)) ?? []).compactMap(\.id)
            anchor = try? container.decodeIfPresent(RotationAnchor.self, forKey: .anchor)
        } else {
            // From 1.2: checked saved styles in library order, then checked
            // built-ins in gallery order, and every saved style when nothing
            // was checked. Counted from the old fixed day, so each widget
            // keeps today's look and its order.
            let flags = (try? container.decodeIfPresent([LegacyFlag].self, forKey: .styles)) ?? []
            let builtIns = (try? container.decodeIfPresent([LossyBuiltIn].self, forKey: .rotatingBuiltIns))?.compactMap(\.style) ?? []
            let mine = zip(styles, flags).filter { $0.1.inRotation == true }.map { LookID.saved($0.0.id) }
            let theirs = WidgetStyle.builtIn.filter(builtIns.contains).map(LookID.builtIn)
            let checked = mine + theirs
            rotation = checked.isEmpty ? styles.map { .saved($0.id) } : checked
            anchor = rotation.isEmpty ? nil : .epoch
        }
        sanitizeRotation()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(styles, forKey: .styles)
        try container.encode(rotation, forKey: .rotation)
        try container.encodeIfPresent(anchor, forKey: .anchor)
    }

    private struct LossyBuiltIn: Decodable {
        var style: WidgetStyle?
        init(from decoder: Decoder) throws { style = try? WidgetStyle(from: decoder) }
    }
}
