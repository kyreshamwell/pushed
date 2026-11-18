import SwiftUI

/// The sheet for changing a look, sized to its content, so the preview above it stays
/// in view. A built-in look is changed as a copy and kept with "Save as my
/// look"; a saved look changes as you go.
struct CustomizeSheet: View {
    let title: String
    /// Where "Look" squares and colors go back to.
    let original: CustomWidgetStyle
    @Binding var style: CustomWidgetStyle
    /// Saved looks only.
    var name: Binding<String>? = nil
    var canSave = true
    /// Built-in looks only: keeps the copy as a saved look.
    var save: (() -> Void)? = nil
    let close: () -> Void
    /// The tallest the sheet can be while the preview above it stays in view.
    var maxHeight: CGFloat = 460

    @State private var squareChoice: SquareOption = .look
    @State private var confirmingDiscard = false
    @State private var showsMore = false
    @State private var detent: PresentationDetent = .height(460)
    @State private var contentHeight: CGFloat = 460
    @State private var taps = 0

    /// Just tall enough for everything, unless that would cover the preview.
    /// Then it stops there and the content scrolls.
    private var compact: PresentationDetent { .height(min(contentHeight, maxHeight)) }
    /// As tall as the sheet can get with the preview still in view. More
    /// options uses it, and its longer list scrolls inside.
    private var roomy: PresentationDetent { .height(maxHeight) }

    private var isBuiltIn: Bool { save != nil }
    private var hasChanges: Bool { style != original }

    private static let swatches: [(name: String, color: RGBAColor)] = [
        ("Green", RGBAColor(hex: 0x39D353)),
        ("Blue", RGBAColor(hex: 0x5B8DEF)),
        ("Violet", RGBAColor(hex: 0xA78BFA)),
        ("Pink", RGBAColor(hex: 0xF472B6)),
        ("Orange", RGBAColor(hex: 0xF2761B)),
        ("Gold", RGBAColor(hex: 0xFACC15)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    squares
                    colors
                    options
                    if let save {
                        saveButton(save)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    let wasCompact = detent != .large && !showsMore
                    contentHeight = ceil(height)
                    if wasCompact { detent = compact }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsMore) {
                MoreOptionsView(style: $style, original: original)
            }
        }
        .presentationDetents([compact, roomy, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Swipes inside the sheet scroll its content instead of resizing it.
        .presentationContentInteraction(.scrolls)
        // No dimming over the preview, so the colors you pick read true.
        .presentationBackgroundInteraction(.enabled(upThrough: roomy))
        .presentationCornerRadius(28)
        .presentationBackground(Color.card)
        .interactiveDismissDisabled(isBuiltIn && hasChanges)
        .onChange(of: showsMore) { _, showing in
            // Taller for the longer list, but never over the preview; back to fit after.
            withAnimation(.snappy) { detent = showing ? roomy : compact }
        }
        .confirmationDialog("Keep your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            if let save, canSave {
                Button("Save as My Look", action: save)
            }
            Button("Discard Changes", role: .destructive, action: close)
        }
        .sensoryFeedback(.selection, trigger: taps)
        .tint(.pushedGreen)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
            Spacer()
            Button("Done") {
                if isBuiltIn && hasChanges {
                    confirmingDiscard = true
                } else {
                    close()
                }
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
        }
    }

    // MARK: - Squares

    private var selectedSquare: SquareOption? {
        if squareChoice.shape(for: original.shape) == style.shape { return squareChoice }
        if style.shape == original.shape { return .look }
        return SquareOption.allCases.first { $0 != .look && $0.shape(for: original.shape) == style.shape }
    }

    private var squares: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetLabel(text: "Squares")
            HStack(spacing: 8) {
                ForEach(SquareOption.allCases) { option in
                    let isOn = selectedSquare == option
                    let shape = option.shape(for: original.shape)
                    Button {
                        taps += 1
                        squareChoice = option
                        withAnimation(.snappy) { style.shape = shape }
                    } label: {
                        VStack(spacing: 8) {
                            CellShape(cornerFraction: shape.cornerFraction, minimumCorner: shape.minimumCorner, form: shape.form)
                                .fill(isOn ? Color.pushedGreen : Color.secondary)
                                .frame(width: 20, height: 20)
                            Text(option.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Color.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isOn ? Color.pushedGreen : Color.clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Color

    /// -1 for the look's own colors, nil for one picked in More options.
    private var selectedSwatch: Int? {
        if style.squares == original.squares { return -1 }
        return Self.swatches.firstIndex { $0.color == style.squares }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetLabel(text: "Color")
            HStack(spacing: 0) {
                swatch(index: -1, label: "Look colors") {
                    Circle().fill(AngularGradient(
                        colors: Self.swatches.map { $0.color.color } + [Self.swatches[0].color.color],
                        center: .center
                    ))
                }
                ForEach(Self.swatches.indices, id: \.self) { index in
                    Spacer(minLength: 2)
                    swatch(index: index, label: Self.swatches[index].name) {
                        Circle().fill(Self.swatches[index].color.color)
                    }
                }
            }
        }
    }

    private func swatch(index: Int, label: String, @ViewBuilder fill: () -> some View) -> some View {
        let isOn = selectedSwatch == index
        return Button {
            taps += 1
            withAnimation(.snappy) {
                style.squares = index < 0 ? original.squares : Self.swatches[index].color
            }
        } label: {
            fill()
                .frame(width: 36, height: 36)
                .overlay {
                    if isOn {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 2)
                            .padding(-5)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Options

    private var options: some View {
        VStack(spacing: 0) {
            if let name {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .submitLabel(.done)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                Divider().padding(.leading, 16)
            }
            Toggle("Glow on busy days", isOn: Binding(
                get: { style.glows },
                set: { glows in
                    taps += 1
                    style.glows = glows
                }
            ))
            .padding(.horizontal, 16)
            .frame(height: 48)
            Divider().padding(.leading, 16)
            Button {
                showsMore = true
            } label: {
                HStack(spacing: 8) {
                    Text("More options")
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    Text("Background, font, spacing")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func saveButton(_ save: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save as my look")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color(red: 0x04 / 255, green: 0x15 / 255, blue: 0x0A / 255))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Color.pushedGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
            if !canSave {
                Text("Your library is full. Delete a look to save another.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The four square choices on the sheet. "Look" is whatever the look
/// started with, and "Square" is the soft corner of Classic and Marks.
enum SquareOption: CaseIterable, Identifiable {
    case look, square, rounded, dot

    var id: Self { self }

    var label: String {
        switch self {
        case .look: "Look"
        case .square: "Square"
        case .rounded: "Rounded"
        case .dot: "Dot"
        }
    }

    func shape(for lookShape: CellShapeChoice) -> CellShapeChoice {
        switch self {
        case .look: lookShape
        case .square: .soft
        case .rounded: .rounded
        case .dot: .dot
        }
    }
}

/// A small uppercase label over a group in the sheet.
struct SheetLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

/// Everything else a look can change: backdrop, the other day colors, type,
/// spacing and how days are drawn.
struct MoreOptionsView: View {
    @Binding var style: CustomWidgetStyle
    let original: CustomWidgetStyle

    var body: some View {
        Form {
            Section {
                ColorPicker("Background", selection: $style.background.color, supportsOpacity: false)
                Toggle("Gradient", isOn: $style.usesGradient.animation())
                if style.usesGradient {
                    ColorPicker("Gradient end", selection: $style.backgroundEnd.color, supportsOpacity: false)
                }
                ColorPicker(style.cellMode == .marks ? "Marks" : "Squares", selection: $style.squares.color, supportsOpacity: false)
                Toggle("Empty day color", isOn: Binding(
                    get: { style.emptySquares != nil },
                    set: { picking in
                        style.emptySquares = picking ? RGBAColor(hex: style.usesLightText ? 0x3A3A4A : 0xE4E4E7) : nil
                    }
                ).animation())
                if style.emptySquares != nil {
                    ColorPicker("Empty days", selection: Binding(
                        get: { style.emptySquares?.color ?? .gray },
                        set: { style.emptySquares = RGBAColor($0) }
                    ), supportsOpacity: false)
                }
                Toggle("Missed day color", isOn: Binding(
                    get: { style.missedSquares != nil },
                    set: { marking in
                        style.missedSquares = marking ? RGBAColor(hex: style.usesLightText ? 0xE5484D : 0xD93D42) : nil
                    }
                ).animation())
                if style.missedSquares != nil {
                    ColorPicker("Missed days", selection: Binding(
                        get: { style.missedSquares?.color ?? .red },
                        set: { style.missedSquares = RGBAColor($0) }
                    ), supportsOpacity: false)
                }
            } header: {
                Text("Colors")
            } footer: {
                if let warning {
                    Text(warning)
                }
            }

            Section("Days") {
                Picker("Days", selection: $style.cellMode) {
                    ForEach(CellMode.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Shape and type") {
                Picker("Shape", selection: $style.shape) {
                    ForEach(CellShapeChoice.allCases) { shape in
                        Text(shape.name).tag(shape)
                    }
                }
                Picker("Font", selection: $style.font) {
                    ForEach(FontChoice.allCases) { font in
                        Text(font.name).tag(font)
                    }
                }
                Picker("Number weight", selection: $style.weight) {
                    ForEach(WeightChoice.allCases) { weight in
                        Text(weight.name).tag(weight)
                    }
                }
                Picker("Spacing", selection: $style.spacing) {
                    ForEach(SpacingChoice.allCases) { spacing in
                        Text(spacing.name).tag(spacing)
                    }
                }
            }

            Section {
                Toggle("Minimal", isOn: $style.minimal)
            } footer: {
                Text("Just the number and the squares.")
            }

            Section {
                Button("Start Over") { style = original }
                    .disabled(style == original)
            }
        }
        .navigationTitle("More Options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Only for colors someone picked: a look's own faint empty days are
    /// meant to be quiet.
    private var warning: String? {
        var notes: [String] = []
        let recolored = style.squares != original.squares || style.background != original.background
            || style.backgroundEnd != original.backgroundEnd || style.usesGradient != original.usesGradient
        if recolored && !style.squaresStandOut {
            notes.append("The squares are faint on this background, so the number uses the text color.")
        }
        if style.emptySquares != original.emptySquares && !style.emptySquaresShow {
            notes.append("Empty days are hard to see on this background.")
        }
        if style.missedSquares != original.missedSquares && !style.missedSquaresShow {
            notes.append("Missed days are hard to see on this background.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
}
