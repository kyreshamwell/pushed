import SwiftUI
import UIKit

/// Everything that isn't a look: days off, reminders and the account.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Streak") {
                NavigationLink {
                    RestDaysView(protection: model.protection, apply: model.apply)
                } label: {
                    LabeledContent("Rest days", value: model.restDaySummary)
                }
                NavigationLink {
                    FreezesView()
                } label: {
                    LabeledContent("Freezes", value: model.freezeSummary)
                }
                NavigationLink {
                    StreakIconPicker(
                        icon: Binding(get: { model.streakIcon }, set: { model.setStreakIcon($0) }),
                        streak: model.history?.streak ?? 0
                    )
                } label: {
                    LabeledContent("Streak icon", value: model.streakIcon == StreakIcon.none ? "None" : model.streakIcon)
                }
                NavigationLink {
                    DayOffMarkView()
                } label: {
                    LabeledContent("Day off mark", value: model.dayOffMark.name)
                }
            }

            remindersSection

            Section("GitHub") {
                NavigationLink {
                    AccountView()
                } label: {
                    LabeledContent("Account", value: model.username)
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    HStack {
                        Text("Refresh now")
                        Spacer()
                        switch model.status {
                        case .loading: ProgressView()
                        case .success: Image(systemName: "checkmark").foregroundStyle(.secondary)
                        default: EmptyView()
                        }
                    }
                }
                .disabled(model.status == .loading)
                if case .failed(let message) = model.status {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if BuildEnvironment.showsDebugTools {
                testingSection
                Section {
                    NavigationLink("Notification debug") { DebugNotificationsView() }
                }
            }

            Section {
            } footer: {
                Text("Pushed \(Self.version)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshPermissionState() }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Daily reminder", isOn: Binding(
                get: { model.notifications.enabled },
                set: { model.setRemindersOn($0) }
            ))
            if model.notifications.enabled {
                DatePicker("Midday check-in", selection: time(\.middayHour, \.middayMinute), displayedComponents: .hourAndMinute)
                DatePicker("Evening deadline", selection: time(\.eveningHour, \.eveningMinute), displayedComponents: .hourAndMinute)
                Toggle("Streak milestones", isOn: setting(\.milestonesEnabled))
                Toggle("Token expiry", isOn: setting(\.tokenAlertsEnabled))
            }
            if model.permissionDenied {
                Button("Notifications are off. Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.red)
            }
        } header: {
            Text("Reminders")
        } footer: {
            if model.notifications.enabled && !model.permissionDenied {
                Text(model.nextReminder)
            }
        }
        .animation(.snappy, value: model.notifications.enabled)
    }

    private func setting(_ key: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.notifications[keyPath: key] },
            set: { value in
                var updated = model.notifications
                updated[keyPath: key] = value
                model.apply(updated)
            }
        )
    }

    /// Builds the new settings and hands them straight to `apply`, never
    /// reading them back, so the time saved is the one just picked.
    private func time(
        _ hour: WritableKeyPath<NotificationSettings, Int>,
        _ minute: WritableKeyPath<NotificationSettings, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: model.notifications[keyPath: hour],
                    minute: model.notifications[keyPath: minute],
                    second: 0, of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var updated = model.notifications
                updated[keyPath: hour] = parts.hour ?? 0
                updated[keyPath: minute] = parts.minute ?? 0
                model.apply(updated)
            }
        )
    }

    // MARK: - Testing

    /// TestFlight and Xcode builds only: a pretend streak everywhere at once.
    private var testingSection: some View {
        Section {
            Picker("Pretend", selection: Binding(
                get: { model.testScenario },
                set: { model.setTestScenario($0) }
            )) {
                ForEach(TestScenario.allCases) { scenario in
                    Text(scenario.name).tag(scenario)
                }
            }
            if model.testScenario != .off {
                Button("Start Test Over") { model.startTestOver() }
            }
        } header: {
            Text("Testing")
        } footer: {
            Text("Pretend data in the app, widgets and reminders. Switches off after 2 days.")
        }
    }
}

/// The monthly freeze: on or off, and whether it's been used.
struct FreezesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Monthly freeze", isOn: Binding(
                    get: { model.protection.freezeEnabled },
                    set: { isOn in
                        var updated = model.protection
                        updated.freezeEnabled = isOn
                        model.apply(updated)
                    }
                ))
                if model.protection.freezeEnabled, let history = model.history {
                    LabeledContent(
                        "This month",
                        value: history.freezeUsedThisMonth.map { "Used \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Unused"
                    )
                }
            } footer: {
                Text("One extra day off a month. Use it from Home on the day or the day after.")
            }
        }
        .navigationTitle("Freezes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How rest days and freezes are marked on the graph.
struct DayOffMarkView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Day off mark", selection: Binding(get: { model.dayOffMark }, set: { model.setDayOffMark($0) })) {
                    ForEach(DayOffMark.allCases) { mark in
                        Text(mark.name).tag(mark)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                legend(StreakDay(level: 2), "Pushed")
                legend(StreakDay(level: 0, off: .rest), "Rest day")
                legend(StreakDay(level: 0, off: .freeze), "Freeze")
                legend(StreakDay(level: 0), "Missed")
            } footer: {
                Text("Days off are marked, never filled in, so your graph still matches GitHub.")
            }
        }
        .navigationTitle("Day Off Mark")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ day: StreakDay, _ text: String) -> some View {
        HStack(spacing: 12) {
            DayCell(day: day, theme: WidgetStyle.classic.theme(for: .dark))
                .environment(\.dayOffMark, model.dayOffMark)
                .frame(width: 22, height: 22)
                .padding(4)
                .background(Color(hex: 0x0D1117), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
        }
    }
}

/// The connected account: who it is, the token, and disconnecting.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var newToken = ""
    @State private var confirmingDisconnect = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: model.username)
                if let expiry = model.tokenExpiry {
                    let days = Calendar.current.dateComponents(
                        [.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: expiry)
                    ).day ?? 0
                    LabeledContent("Token expires") {
                        Text(days <= 0 ? "Expired" : "In \(days) day\(days == 1 ? "" : "s")")
                            .foregroundStyle(days <= 5 ? .red : days <= 10 ? .orange : .secondary)
                    }
                }
            }

            Section {
                SecureField("Paste a new token", text: $newToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Token") {
                    let token = newToken
                    newToken = ""
                    Task { await model.updateToken(token) }
                }
                .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty || model.status == .loading)
                Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=read:user&description=Pushed")!) {
                    Label("Make a token", systemImage: "arrow.up.right")
                }
            } header: {
                Text("Update token")
            } footer: {
                if case .failed(let message) = model.status {
                    Text(message).foregroundStyle(.red)
                }
            }

            Section {
                Button("Disconnect", role: .destructive) { confirmingDisconnect = true }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect GitHub?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
        } message: {
            Text("Your widgets stop updating until you connect again.")
        }
    }
}
