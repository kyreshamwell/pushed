import SwiftUI
import WidgetKit

/// The screens reached from Home.
enum Route: Hashable {
    case styles
    case settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    @State private var store = StyleLibraryStore()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.isConnected {
                    HomeView()
                } else {
                    OnboardingView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .styles:
                    StylesView(data: model.previewData(), selection: todaysLook)
                case .settings:
                    SettingsView()
                }
            }
        }
        .environment(model)
        .environment(store)
        .environment(\.dayOffMark, model.dayOffMark)
        .tint(.pushedGreen)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.refresh()
                Task { await model.becameActive() }
            case .background, .inactive:
                store.flush()
            @unknown default:
                break
            }
        }
        .task { await model.refreshPermissionState() }
        .onChange(of: model.isConnected) { _, connected in
            if !connected { path = NavigationPath() }
        }
    }

    /// Styles opens on what the widget wears today.
    private var todaysLook: LookID {
        store.library.rotationSchedule(from: Date()).first ?? .builtIn(.classic)
    }
}

/// The live widget, today, the numbers and the way into Styles.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(StyleLibraryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if model.testScenario != .off {
                        testBanner
                    }
                    if let snapshot = model.shownSnapshot, let history = model.history {
                        widget
                        if history.canSaveStreak {
                            rescueCard(history)
                        } else if let kind = history.claim(daysAgo: 1) {
                            claimedYesterday(kind)
                        }
                        TodayCard(history: history, snapshot: snapshot)
                        statTiles(history, snapshot: snapshot)
                        stylesRow
                        Spacer(minLength: 0)
                        syncLine(snapshot)
                    }
                }
                .padding(.bottom, 24)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .refreshable { await model.refresh() }
        }
        .background(Color.page)
        .background(BackButtonTitle(title: "Home"))
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: model.history?.today)
    }

    private var header: some View {
        HStack {
            Text("Pushed")
                .font(.largeTitle.weight(.heavy))
            Spacer()
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.card, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 18)
    }

    private var testBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Test data: \(model.testScenario.name)", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
            if let ends = TestScenario.endsAt() {
                Text("Ends \(ends.formatted(.dateTime.weekday(.wide).hour().minute()))")
                    .font(.caption)
            }
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card(radius: 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Widget

    private var widget: some View {
        VStack(spacing: 12) {
            NavigationLink(value: Route.styles) {
                ScaledWidget(
                    look: store.library.rotationSchedule(from: Date()).first.flatMap(store.library.look(of:))
                        ?? WidgetLook(.classic),
                    family: .systemMedium,
                    scale: 1,
                    data: model.previewData()
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.16), radius: 28, y: 16)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityLabel("Your widget. Opens Styles.")
            Text(HomeWords.rotationCaption(store.library, on: Date()))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    // MARK: - Yesterday

    private func rescueCard(_ history: StreakHistory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                StatusIcon(symbol: "exclamationmark", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save your \(history.streakBeforeBreak)-day streak")
                        .font(.headline)
                    Text("Yesterday is empty. Cover it before midnight.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                // A claim that takes today's day off away says so, since
                // today goes back to needing a push.
                if history.canClaim(.rest, daysAgo: 1) {
                    Button(
                        history.claimMovesTodaysDayOff(.rest, daysAgo: 1) ? "Move today's rest day" : "Use a rest day",
                        systemImage: "moon.zzz"
                    ) { model.claim(.rest, daysAgo: 1) }
                }
                if history.canClaim(.freeze, daysAgo: 1) {
                    Button(
                        history.claimMovesTodaysDayOff(.freeze, daysAgo: 1) ? "Move today's freeze" : "Use a freeze",
                        systemImage: "snowflake"
                    ) { model.claim(.freeze, daysAgo: 1) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 54)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
        .padding(.horizontal, 16)
    }

    private func claimedYesterday(_ kind: DayOff) -> some View {
        HStack(spacing: 14) {
            StatusIcon(symbol: kind == .rest ? "moon.zzz.fill" : "snowflake", tint: kind == .rest ? .indigo : .cyan)
            Text(kind == .rest ? "Yesterday was a rest day" : "Yesterday was frozen")
                .font(.subheadline)
            Spacer(minLength: 0)
            Button("Undo") { model.undoClaim(daysAgo: 1) }
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .card()
        .padding(.horizontal, 16)
    }

    // MARK: - Numbers

    private func statTiles(_ history: StreakHistory, snapshot: ContributionSnapshot) -> some View {
        HStack(spacing: 10) {
            StatTile(value: history.streak, label: "Current streak")
            StatTile(value: history.bestStreak, label: "Best streak")
            StatTile(value: snapshot.totalContributions, label: "This year")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Styles

    private var stylesRow: some View {
        NavigationLink(value: Route.styles) {
            HStack(spacing: 14) {
                swatches
                VStack(alignment: .leading, spacing: 2) {
                    Text("Styles")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(HomeWords.stylesSummary(store.library))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .padding(.horizontal, 16)
    }

    /// The looks in the rotation, or the built-ins when nothing rotates.
    private var swatches: some View {
        let rotating = store.library.rotationLooks
        let looks = Array((rotating.isEmpty ? WidgetStyle.builtIn.map(WidgetLook.init) : rotating).prefix(5))
        return HStack(spacing: -10) {
            ForEach(looks.indices, id: \.self) { index in
                LookSwatch(look: looks[index])
                    .padding(2)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
    }

    private func syncLine(_ snapshot: ContributionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 4) {
                Text("Synced \(HomeWords.synced(snapshot.fetchedAt, now: context.date)) · pull to refresh")
                if case .failed(let message) = model.status {
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
        }
    }
}

/// "Pushed today", "Not yet today", or the day off, with the actions that
/// apply to today.
struct TodayCard: View {
    @Environment(AppModel.self) private var model
    let history: StreakHistory
    let snapshot: ContributionSnapshot

    var body: some View {
        let words = HomeWords.today(history, count: HomeWords.todayCount(snapshot, history: history))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                StatusIcon(symbol: words.symbol, tint: tint(words.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(words.title)
                        .font(.headline)
                    if let detail = words.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if case .off = history.today, history.claim(daysAgo: 0) != nil {
                    Button("Undo") { model.undoClaim(daysAgo: 0) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if history.today == .pending, history.todayCanKeepStreak, canTakeToday {
                HStack(spacing: 8) {
                    if history.canClaim(.rest, daysAgo: 0) {
                        Button("Rest day", systemImage: "moon.zzz") { model.claim(.rest, daysAgo: 0) }
                    }
                    if history.canClaim(.freeze, daysAgo: 0) {
                        Button("Use a freeze", systemImage: "snowflake") { model.claim(.freeze, daysAgo: 0) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 54)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var canTakeToday: Bool {
        history.canClaim(.rest, daysAgo: 0) || history.canClaim(.freeze, daysAgo: 0)
    }

    private func tint(_ kind: HomeWords.TodayKind) -> Color {
        switch kind {
        case .pushed: .pushedGreen
        case .pending: .secondary
        case .rest: .indigo
        case .freeze: .cyan
        }
    }
}

/// A symbol in a softly tinted circle, leading a card.
struct StatusIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.16), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// One of the three numbers under the widget.
struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 28, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
