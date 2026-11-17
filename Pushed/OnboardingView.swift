import SwiftUI

/// First launch, or after disconnecting: a username, a token, and the widget.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: Field?

    private enum Field { case username, token }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pushed")
                        .font(.largeTitle.weight(.heavy))
                    Text("Your GitHub streak, on your home screen.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 18)

                ScaledWidget(look: WidgetLook(.classic), family: .systemMedium, scale: 1, data: model.previewData())
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.16), radius: 28, y: 16)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                step(1, "Your GitHub username") {
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .token }
                        .fieldStyle()
                    Link(destination: URL(string: "https://github.com/settings/profile")!) {
                        Label("Find it on GitHub", systemImage: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                step(2, "A token") {
                    SecureField("Paste your token", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .token)
                        .submitLabel(.go)
                        .onSubmit(connect)
                        .fieldStyle()
                    Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=read:user&description=Pushed")!) {
                        Label("Make a token", systemImage: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("Tap Generate token, then copy it. It's read-only and kept in your Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Button(action: connect) {
                        ZStack {
                            if model.status == .loading {
                                ProgressView().tint(.black)
                            } else {
                                Text("Connect")
                            }
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(red: 0x04 / 255, green: 0x15 / 255, blue: 0x0A / 255))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.pushedGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(model.username.isEmpty || model.token.isEmpty || model.status == .loading)
                    .opacity(model.username.isEmpty || model.token.isEmpty ? 0.5 : 1)

                    if case .failed(let message) = model.status {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                step(3, "Add the widget") {
                    Text("Hold your home screen, tap Edit, then Add Widget, and find Pushed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NavigationLink(value: Route.styles) {
                        Label("See the looks", systemImage: "square.grid.2x2")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if BuildEnvironment.showsDebugTools {
                    NavigationLink("Notification debug") { DebugNotificationsView() }
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.page)
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func connect() {
        guard !model.username.isEmpty, !model.token.isEmpty else { return }
        focus = nil
        Task { await model.refresh() }
    }

    private func step(_ number: Int, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.pushedGreen)
                    .frame(width: 26, height: 26)
                    .background(Color.pushedGreen.opacity(0.16), in: Circle())
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }
}

private extension View {
    /// A text field on a card, the way Settings draws them.
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
