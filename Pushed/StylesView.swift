import SwiftUI
import WidgetKit

/// Picking, rotating and customizing looks, all in one place. The look on
/// show is one row, like the card in Apple Pay; tapping it lists every look,
/// and the circle on a row adds it to the rotation or takes it out.
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
    @State private var rotationTaps = 0
    @State private var saves = 0

    init(data: PreviewData, selection: LookID) {
        self.data = data
        _selection = State(initialValue: selection)
    }

    /// Room under the preview for the Customize sheet, from the screen's height.
    @State private var sheetRoom: CGFloat = 460
    /// The list of every look, like the card list in Apple Pay.
    @State private var showsAllLooks = false
    /// "New look" was tapped in the list; it opens once the list is gone.
    @State private var newLookPending = false
    /// "Customize" or "Edit" was picked in the list; it opens once the list is gone.
    @State private var customizePending = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                preview
                    .id("preview")
                sizeSwitch
                    .padding(.bottom, 18)
                lookRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
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
        .sheet(isPresented: $showsAllLooks, onDismiss: {
            if newLookPending {
                newLookPending = false
                createLook()
            } else if customizePending {
                customizePending = false
                openCustomize()
            }
        }) {
            lookList
        }
        .navigationTitle("Styles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $customizing, onDismiss: { draft = nil }) { target in
            customizeSheet(for: target)
        }
        .confirmationDialog(
            "Delete \(deleting?.displayName ?? "this look")?",
            isPresented: Binding(get: { deleting != nil && !showsAllLooks }, set: { if !$0 { deleting = nil } }),
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

    private var allLooks: [(id: LookID, look: WidgetLook)] {
        WidgetStyle.builtIn.map { (LookID.builtIn($0), WidgetLook($0)) }
            + store.library.styles.map { (LookID.saved($0.id), WidgetLook($0)) }
    }

    /// The look on show, as one row like the card in Apple Pay. Tapping it
    /// opens the list of every look.
    private var lookRow: some View {
        let current = store.library.look(of: selection) ?? WidgetLook(.classic)
        return Button { showsAllLooks = true } label: {
            HStack(spacing: 14) {
                LookThumb(look: current, data: data)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(current.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(allLooks.count) looks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 68)
            .frame(maxWidth: .infinity)
            .card(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel("Look, \(current.name). Choose another")
    }

    /// Every look as a compact row with a small picture of it, like the list
    /// of cards in Apple Pay.
    private var lookList: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(allLooks, id: \.id) { item in
                        lookTile(item.id, look: item.look)
                            .contextMenu { listMenu(item.id) }
                    }
                    newLookTile
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Text("The circle adds a look to your rotation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
            }
            .navigationTitle("Looks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsAllLooks = false }
                }
            }
            .confirmationDialog(
                "Delete \(deleting?.displayName ?? "this look")?",
                isPresented: Binding(get: { deleting != nil && showsAllLooks }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { saved in
                Button("Delete Look", role: .destructive) { delete(saved.id) }
            } message: { _ in
                Text("Widgets using it switch to your first saved look.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(.pushedGreen)
    }

    /// One look in the grid: the small widget wearing it, its name, and the
    /// rotation circle. The look on show gets a ring instead of a checkmark.
    private func lookTile(_ id: LookID, look: WidgetLook) -> some View {
        let inRotation = store.library.isInRotation(id)
        let isOn = selection == id
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ScaledWidget(look: look, family: .systemSmall,
                             scale: geo.size.width / WidgetPreviewCard.size(for: .systemSmall).width, data: data)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isOn ? Color.pushedGreen : .clear, lineWidth: 2.5)
                    .padding(-5)
            }
            HStack(spacing: 4) {
                Text(look.name)
                    .font(.subheadline.weight(isOn ? .bold : .medium))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { toggleRotation(id, keepSelection: true) } label: {
                    RotationCircle(isOn: inRotation)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -10)
                .accessibilityLabel(inRotation ? "Remove \(look.name) from rotation" : "Add \(look.name) to rotation")
            }
            .padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { pickLook(id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show \(look.name)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var newLookTile: some View {
        Button {
            newLookPending = true
            showsAllLooks = false
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                Text("New Look")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!store.library.canAdd)
    }

    /// The list's long-press menu. Customizing closes the list first, so the
    /// Customize sheet opens over the preview.
    @ViewBuilder
    private func listMenu(_ id: LookID) -> some View {
        let isSaved: Bool = { if case .saved = id { return true } else { return false } }()
        Button(isSaved ? "Edit" : "Customize", systemImage: "slider.horizontal.3") {
            withAnimation(.easeOut(duration: 0.2)) { selection = id }
            customizePending = true
            showsAllLooks = false
        }
        rotationButton(id)
        if case .saved(let uuid) = id, let saved = store.library.styles.first(where: { $0.id == uuid }) {
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(uuid) }
                .disabled(!store.library.canAdd)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = saved }
                .disabled(!store.library.canRemove)
        }
    }

    private func pickLook(_ id: LookID) {
        withAnimation(.easeOut(duration: 0.2)) { selection = id }
        showsAllLooks = false
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

    private func toggleRotation(_ id: LookID, keepSelection: Bool = false) {
        rotationTaps += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            store.update { $0.toggleRotation(id) }
            if !keepSelection { selection = id }
        }
    }

    private func createLook() {
        var created: UUID?
        store.update { created = $0.add()?.id }
        guard let created else { return }
        let id = LookID.saved(created)
        withAnimation(.easeOut(duration: 0.2)) { selection = id }
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
    }

    private func duplicate(_ id: UUID) {
        var copy: UUID?
        withAnimation(.snappy) {
            store.update { copy = $0.duplicate(id)?.id }
        }
        guard let copy else { return }
        select(.saved(copy))
    }

    private func delete(_ id: UUID) {
        withAnimation(.snappy) {
            store.update { $0.remove(id) }
            if selection == .saved(id) {
                selection = .builtIn(.classic)
            }
        }
    }
}

/// What the Customize sheet is working on, and where it started.
struct CustomizeTarget: Identifiable {
    let id: LookID
    let original: CustomWidgetStyle
}

/// Green with a check when the look is in the rotation, an empty ring when not.
struct RotationCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.pushedGreen : Color.white.opacity(0.18))
            Circle()
                .strokeBorder(isOn ? Color.pushedGreen : Color.white.opacity(0.85), lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .background(.ultraThinMaterial, in: Circle())
        .scaleEffect(isOn ? 1 : 0.94)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
    }
}

/// A small picture of a look: its widget at thumbnail size, like the card
/// art in Apple Pay's list.
struct LookThumb: View {
    let look: WidgetLook
    let data: PreviewData

    var body: some View {
        let width: CGFloat = 64
        ScaledWidget(
            look: look, family: .systemMedium,
            scale: width / WidgetPreviewCard.size(for: .systemMedium).width,
            data: data
        )
        .frame(width: width, height: width * WidgetPreviewCard.size(for: .systemMedium).height / WidgetPreviewCard.size(for: .systemMedium).width)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
