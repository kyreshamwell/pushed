import SwiftUI
import WidgetKit

/// Picking, rotating and customizing looks, all in one place. Tapping a card
/// previews it; the circle on a card adds it to the rotation or takes it out.
struct StylesView: View {
    @Environment(StyleLibraryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    let data: PreviewData

    @State private var selection: LookID
    @State private var family: WidgetFamily = .systemMedium
    @State private var customizing: CustomizeTarget?
    /// A built-in look being customized. The preview shows it until it's
    /// saved or dropped.
    @State private var draft: CustomWidgetStyle?
    @State private var deleting: SavedStyle?
    @State private var showsRotationInfo = false
    @State private var scrollTarget: LookID?
    @State private var rotationTaps = 0
    @State private var saves = 0

    init(data: PreviewData, selection: LookID) {
        self.data = data
        _selection = State(initialValue: selection)
    }

    /// Room under the preview for the Customize sheet, from the screen's height.
    @State private var sheetRoom: CGFloat = 460

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                preview
                    .id("preview")
                sizeSwitch
                    .padding(.bottom, 18)
                looksHeader
                looksRow
                rotationCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                customizeButton
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            // The scroll view runs from under the navigation bar to the bottom
            // edge; keep the preview (300pt) and a little air above the sheet.
            proxy.size.height + proxy.safeAreaInsets.bottom - Self.previewHeight - 12
        } action: { sheetRoom = max($0, 320) }
        .onChange(of: customizing != nil) { _, open in
            if open { withAnimation(.snappy) { proxy.scrollTo("preview", anchor: .top) } }
        }
        }
        .background(Color.page)
        .navigationTitle("Styles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $customizing, onDismiss: { draft = nil }) { target in
            customizeSheet(for: target)
        }
        .confirmationDialog(
            "Delete \(deleting?.displayName ?? "this look")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { saved in
            Button("Delete Look", role: .destructive) { delete(saved.id) }
        } message: { _ in
            Text("Widgets using it switch to your first saved look.")
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.selection, trigger: family)
        .sensoryFeedback(.impact(weight: .light), trigger: rotationTaps)
        .sensoryFeedback(.success, trigger: saves)
        .onDisappear { store.flush() }
    }

    // MARK: - Preview

    private var shownLook: WidgetLook {
        if let draft, customizing != nil {
            var look = WidgetLook(.custom)
            look.custom = draft
            return look
        }
        return store.library.look(of: selection) ?? WidgetLook(.classic)
    }

    private var previewScale: CGFloat {
        switch family {
        case .systemSmall: 1.4
        case .systemLarge: 0.72
        default: 1
        }
    }

    private var preview: some View {
        ZStack {
            ScaledWidget(look: shownLook, family: family, scale: previewScale, data: data)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 26, y: 16)
                .id(PreviewKey(selection: selection, family: family))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.previewHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(selectedName), \(familyName)")
    }

    private static let previewHeight: CGFloat = 300

    private struct PreviewKey: Hashable {
        let selection: LookID
        let family: WidgetFamily
    }

    private var familyName: String {
        switch family {
        case .systemSmall: "Small"
        case .systemLarge: "Large"
        default: "Medium"
        }
    }

    private var sizeSwitch: some View {
        Picker("Size", selection: $family.animation(.spring(response: 0.34, dampingFraction: 0.86))) {
            Text("Small").tag(WidgetFamily.systemSmall)
            Text("Medium").tag(WidgetFamily.systemMedium)
            Text("Large").tag(WidgetFamily.systemLarge)
        }
        .pickerStyle(.segmented)
        .frame(width: 256)
    }

    // MARK: - Looks

    private var looksHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Looks")
                .font(.title3.weight(.bold))
            Spacer()
            Text("Tap to preview · circle to rotate")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }

    private var looksRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(WidgetStyle.builtIn) { style in
                        card(.builtIn(style), look: WidgetLook(style))
                            .contextMenu { builtInMenu(style) }
                    }
                    ForEach(store.library.styles) { saved in
                        card(.saved(saved.id), look: WidgetLook(saved))
                            .contextMenu { savedMenu(saved) }
                    }
                    newCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
    }

    private func card(_ id: LookID, look: WidgetLook) -> some View {
        LookCard(
            look: look,
            isSelected: selection == id,
            isInRotation: store.library.isInRotation(id),
            data: data,
            select: { select(id) },
            toggle: { toggleRotation(id) }
        )
        .equatable()
        .id(id)
    }

    private var newCard: some View {
        Button(action: createLook) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("New")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(width: 92, height: 92)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!store.library.canAdd)
        .accessibilityLabel("New look")
    }

    @ViewBuilder
    private func builtInMenu(_ style: WidgetStyle) -> some View {
        Button("Customize", systemImage: "slider.horizontal.3") {
            select(.builtIn(style))
            openCustomize()
        }
        rotationButton(.builtIn(style))
    }

    @ViewBuilder
    private func savedMenu(_ saved: SavedStyle) -> some View {
        Button("Edit", systemImage: "slider.horizontal.3") {
            select(.saved(saved.id))
            openCustomize()
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(saved.id) }
            .disabled(!store.library.canAdd)
        rotationButton(.saved(saved.id))
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = saved }
            .disabled(!store.library.canRemove)
    }

    private func rotationButton(_ id: LookID) -> some View {
        let isOn = store.library.isInRotation(id)
        return Button(
            isOn ? "Remove from Rotation" : "Add to Rotation",
            systemImage: isOn ? "minus.circle" : "plus.circle"
        ) { toggleRotation(id) }
    }

    // MARK: - Rotation

    private var rotationCard: some View {
        let schedule = store.library.rotationSchedule(from: data.now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Rotation")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(rotationNote(schedule.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Button {
                    showsRotationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-10)
                .accessibilityLabel("About the rotation")
                .popover(isPresented: $showsRotationInfo, arrowEdge: .top) {
                    Text("A widget rotates when its Style is Daily Rotation in Edit Widget.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 240)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            if schedule.isEmpty {
                Text("Tap the circle on a look to add it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(schedule.enumerated()), id: \.element) { offset, id in
                            if let look = store.library.look(of: id) {
                                chip(look, day: offset)
                                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }

    private func chip(_ look: WidgetLook, day offset: Int) -> some View {
        HStack(spacing: 8) {
            LookSwatch(look: look, size: 22, cornerRadius: 11)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            Text(dayLabel(offset))
                .font(.caption.weight(.semibold))
                .foregroundStyle(offset == 0 ? Color.pushedGreen : Color.secondary)
            Text(look.name)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(Color.raised.opacity(offset == 0 ? 1 : 0.55), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func rotationNote(_ count: Int) -> String {
        switch count {
        case 0: "Off"
        case 1: "Stays on one look"
        default: "\(count) looks · changes at midnight"
        }
    }

    /// Today, then the weekday for the rest of this week, then dates.
    private func dayLabel(_ offset: Int) -> String {
        if offset == 0 { return "Today" }
        let day = Calendar.current.date(byAdding: .day, value: offset, to: data.now) ?? data.now
        return offset < 7
            ? day.formatted(.dateTime.weekday(.abbreviated))
            : day.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Customize

    private var selectedName: String {
        store.library.look(of: selection)?.name ?? "Look"
    }

    private var customizeButton: some View {
        Button(action: openCustomize) {
            Label("Customize \(selectedName)", systemImage: "slider.vertical.3")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private func openCustomize() {
        let original: CustomWidgetStyle
        switch selection {
        case .builtIn(let style):
            original = CustomWidgetStyle.seeded(from: style)
            draft = original
        case .saved(let id):
            original = store.library[id]?.style ?? .default
        }
        customizing = CustomizeTarget(id: selection, original: original)
    }

    @ViewBuilder
    private func customizeSheet(for target: CustomizeTarget) -> some View {
        switch target.id {
        case .builtIn(let style):
            CustomizeSheet(
                title: "Customize \(style.name)",
                original: target.original,
                style: Binding(get: { draft ?? target.original }, set: { draft = $0 }),
                canSave: store.library.canAdd,
                save: { saveDraft(from: style) },
                close: { customizing = nil },
                maxHeight: sheetRoom
            )
        case .saved(let id):
            CustomizeSheet(
                title: "Customize \(store.library[id]?.displayName ?? "Look")",
                original: target.original,
                style: Binding(
                    get: { store.library[id]?.style ?? target.original },
                    set: { style in store.update { $0[id]?.style = style } }
                ),
                name: Binding(
                    get: { store.library[id]?.name ?? "" },
                    set: { name in store.update { $0[id]?.name = name } }
                ),
                close: { customizing = nil },
                maxHeight: sheetRoom
            )
        }
    }

    // MARK: - Changes

    private func select(_ id: LookID) {
        guard id != selection else { return }
        withAnimation(.easeOut(duration: 0.2)) { selection = id }
    }

    private func toggleRotation(_ id: LookID) {
        rotationTaps += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            store.update { $0.toggleRotation(id) }
            selection = id
        }
    }

    private func createLook() {
        var created: UUID?
        store.update { created = $0.add()?.id }
        guard let created else { return }
        let id = LookID.saved(created)
        withAnimation(.easeOut(duration: 0.2)) { selection = id }
        scrollTarget = id
        customizing = CustomizeTarget(id: id, original: store.library[created]?.style ?? .default)
    }

    private func saveDraft(from style: WidgetStyle) {
        guard let draft else { return }
        var created: UUID?
        store.update { created = $0.add(draft, named: "My \(style.name)")?.id }
        guard let created else { return }
        let id = LookID.saved(created)
        saves += 1
        customizing = nil
        self.draft = nil
        withAnimation(.easeOut(duration: 0.2)) { selection = id }
        scrollTarget = id
    }

    private func duplicate(_ id: UUID) {
        var copy: UUID?
        withAnimation(.snappy) {
            store.update { copy = $0.duplicate(id)?.id }
        }
        guard let copy else { return }
        select(.saved(copy))
        scrollTarget = .saved(copy)
    }

    private func delete(_ id: UUID) {
        withAnimation(.snappy) {
            store.update { $0.remove(id) }
            if selection == .saved(id) {
                selection = .builtIn(.classic)
                scrollTarget = selection
            }
        }
    }
}

/// What the Customize sheet is working on, and where it started.
struct CustomizeTarget: Identifiable {
    let id: LookID
    let original: CustomWidgetStyle
}

/// One look in the row: the real widget in miniature with its name, and the
/// circle that adds it to the rotation.
struct LookCard: View, Equatable {
    let look: WidgetLook
    let isSelected: Bool
    let isInRotation: Bool
    let data: PreviewData
    let select: () -> Void
    let toggle: () -> Void

    static func == (lhs: LookCard, rhs: LookCard) -> Bool {
        lhs.look == rhs.look && lhs.isSelected == rhs.isSelected
            && lhs.isInRotation == rhs.isInRotation && lhs.data == rhs.data
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ScaledWidget(look: look, family: .systemSmall, scale: 92 / 170, data: data)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 20.5, style: .continuous)
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .padding(-4.5)
                                .transition(.opacity)
                        }
                    }
                Text(look.name)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 96)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Preview \(look.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            Button(action: toggle) {
                RotationCircle(isOn: isInRotation)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .offset(x: 12, y: -10)
            .accessibilityLabel(isInRotation ? "Remove \(look.name) from rotation" : "Add \(look.name) to rotation")
        }
    }
}

/// Green with a check when the look is in the rotation, an empty ring when not.
struct RotationCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.pushedGreen : Color.black.opacity(0.55))
            Circle()
                .strokeBorder(isOn ? Color.pushedGreen : Color.white.opacity(0.7), lineWidth: 2)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .scaleEffect(isOn ? 1 : 0.94)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
    }
}
