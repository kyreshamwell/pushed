import Observation
import SwiftUI
import UIKit
import WidgetKit

/// Everything the app's screens read and change, outside the style library:
/// the account, the data, days off, reminders and the debug test mode.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case idle
        case loading
        case success
        case failed(String)
    }

    var username: String = AppModel.initialUsername
    var token: String = AppModel.initialToken
    private(set) var snapshot: ContributionSnapshot? = ContributionSnapshot.load()
    private(set) var streakIcon: String = AppConfig.streakIcon
    private(set) var protection = AppConfig.streakProtection
    private(set) var testScenario = TestScenario.current
    private(set) var dayOffMark = AppConfig.dayOffMark
    private(set) var status: Status = .idle
    private(set) var notifications: NotificationSettings = AppConfig.notificationSettings
    private(set) var permissionDenied = false
    private(set) var tokenExpiry: Date? = AppConfig.tokenExpiry

    var isConnected: Bool {
        !username.isEmpty && !token.isEmpty && snapshot != nil
    }

    /// The real data, or the pretend data while a test is running.
    var shownSnapshot: ContributionSnapshot? {
        testScenario.snapshot(replacing: snapshot)
    }

    /// One reading for every screen, the same one the widget and the
    /// reminders work from.
    var history: StreakHistory? {
        shownSnapshot?.history(protection: protection)
    }

    /// What the previews draw: real data when connected, sample data before.
    func previewData(now: Date = Date()) -> PreviewData {
        PreviewData(
            snapshot: shownSnapshot ?? .sample(),
            protection: protection,
            icon: streakIcon,
            dayOffMark: dayOffMark,
            now: now
        )
    }

    private static var initialUsername: String {
        let stored = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey) ?? ""
        #if DEBUG
        if DemoMode.isRequested && stored.isEmpty { return DemoMode.username }
        #endif
        return stored
    }

    private static var initialToken: String {
        #if DEBUG
        // Held in memory only, so demo mode never touches the Keychain.
        if DemoMode.isRequested { return "demo" }
        #endif
        return KeychainHelper.read(account: AppConfig.keychainAccount) ?? ""
    }

    // MARK: - Coming back to the app

    /// Notifications are turned back on in iOS Settings, outside the app, so
    /// the return trip is the only moment to notice. A test may also have
    /// switched itself off while the app was away.
    func becameActive() async {
        await refreshPermissionState()
        TestScenario.expireIfNeeded()
        if testScenario != TestScenario.current {
            testScenario = TestScenario.current
            protection = AppConfig.streakProtection
        }
    }

    func refreshPermissionState() async {
        permissionDenied = await SystemNotificationCenter.authorizationStatus() == .denied
    }

    // MARK: - Days off

    /// Single write path for rest days and freezes. A claim changes what
    /// today's reminders say under identifiers already queued, so the day
    /// slots are dropped and planned again.
    func apply(_ updated: StreakProtection) {
        let updated = testScenario == .off ? updated : TestScenario.normalized(updated)
        protection = updated
        AppConfig.streakProtection = updated
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await NotificationScheduler(center: SystemNotificationCenter()).resetDaySlots()
            await NotificationCoordinator.reconcile()
        }
    }

    func claim(_ kind: DayOff, daysAgo: Int) {
        guard let date = history?.date(daysAgo: daysAgo) else { return }
        var updated = protection
        updated.claim(kind, on: date)
        apply(updated)
    }

    func undoClaim(daysAgo: Int) {
        guard let date = history?.date(daysAgo: daysAgo) else { return }
        var updated = protection
        updated.removeClaim(on: date)
        apply(updated)
    }

    var restDaySummary: String {
        let chosen = protection.chosenWeekdays
        return chosen.isEmpty ? "Off" : Weekday.shortNames(chosen)
    }

    var freezeSummary: String {
        guard protection.freezeEnabled else { return "Off" }
        guard let history else { return "On" }
        return history.freezeUsedThisMonth == nil ? "1 left" : "0 left"
    }

    // MARK: - Widget extras

    func setStreakIcon(_ icon: String) {
        streakIcon = icon
        AppConfig.streakIcon = icon
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setDayOffMark(_ mark: DayOffMark) {
        dayOffMark = mark
        AppConfig.dayOffMark = mark
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Testing

    func setTestScenario(_ scenario: TestScenario) {
        TestScenario.switchTo(scenario)
        testScenario = scenario
        refreshAfterTestChange()
    }

    func startTestOver() {
        TestScenario.startOver()
        refreshAfterTestChange()
    }

    private func refreshAfterTestChange() {
        protection = AppConfig.streakProtection
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await NotificationScheduler(center: SystemNotificationCenter()).resetDaySlots()
            await NotificationCoordinator.reconcile()
        }
    }

    // MARK: - Reminders

    /// Single write path for reminder settings. The day slots reuse the same
    /// identifiers, so they're dropped before reconciling, or the old time
    /// would stay queued.
    func apply(_ settings: NotificationSettings) {
        notifications = settings
        AppConfig.notificationSettings = settings
        Task {
            await NotificationScheduler(center: SystemNotificationCenter()).resetDaySlots()
            await NotificationCoordinator.reconcile()
        }
    }

    func setRemindersOn(_ isOn: Bool) {
        guard isOn else {
            var updated = notifications
            updated.enabled = false
            apply(updated)
            return
        }
        Task {
            let granted = await SystemNotificationCenter.requestAuthorization()
            permissionDenied = !granted
            var updated = notifications
            updated.enabled = granted
            apply(updated)
        }
    }

    /// What fires next, from the same planner the scheduler runs, so "nothing
    /// happened" can be told apart from a time that's already gone.
    var nextReminder: String {
        let plan = NotificationPlanner.plan(
            NotificationContext(
                snapshot: shownSnapshot,
                protection: protection,
                settings: notifications,
                tokenExpiry: AppConfig.tokenExpiry,
                lastCelebratedStreak: AppConfig.lastCelebratedStreak,
                authFailed: AppConfig.authFailed,
                lastAuthAlertAt: AppConfig.lastAuthAlertAt,
                now: Date()
            )
        ).filter { $0.id.hasPrefix("daily-") }

        guard let next = plan.min(by: { $0.fireDate < $1.fireDate }) else {
            switch history?.today {
            case .pushed: return "You've pushed today. Reminders start again tomorrow."
            case .off: return "Today is a day off. Reminders start again tomorrow."
            default: break
            }
            if AppConfig.authFailed { return "Paused until you reconnect GitHub." }
            return "Nothing left today."
        }
        return "Next at \(next.fireDate.formatted(date: .omitted, time: .shortened)): \(next.title)"
    }

    // MARK: - Account

    func disconnect() {
        KeychainHelper.delete(account: AppConfig.keychainAccount)
        AppConfig.sharedDefaults.removeObject(forKey: AppConfig.usernameDefaultsKey)
        AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
        AppConfig.resetNotificationState()
        AppConfig.forgetAccountHistory()
        protection = AppConfig.streakProtection
        username = ""
        token = ""
        snapshot = nil
        tokenExpiry = nil
        status = .idle
        Task { await NotificationScheduler(center: SystemNotificationCenter()).removeAllManaged() }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Swaps in a new token for the same account and checks it with GitHub.
    func updateToken(_ newToken: String) async {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        token = trimmed
        await refresh()
    }

    func refresh() async {
        #if DEBUG
        if DemoMode.isRequested { return }
        #endif
        guard !username.isEmpty, !token.isEmpty else { return }

        // Reminder times and the streak icon belong to the phone and stay.
        // Milestones, token dates and auth state belong to the account, and
        // carrying them over would hold back the new account's milestones.
        let previous = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let switchedAccount = previous.map { $0.lowercased() != username.lowercased() } ?? false
        if switchedAccount {
            AppConfig.resetNotificationState()
            AppConfig.forgetAccountHistory()
            protection = AppConfig.streakProtection
            AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
            await NotificationScheduler(center: SystemNotificationCenter()).removeAllManaged()
        }

        let isFirstConnect = snapshot == nil || switchedAccount
        AppConfig.sharedDefaults.set(username, forKey: AppConfig.usernameDefaultsKey)

        // Without the token in the Keychain the widget and the background
        // refresh have nothing to read, so stop before the network call.
        guard KeychainHelper.save(token, account: AppConfig.keychainAccount) else {
            let code = KeychainHelper.lastSaveStatus.map { " (error \($0))" } ?? ""
            status = .failed("Couldn't save your token to the Keychain\(code). Try again.")
            return
        }
        status = .loading

        do {
            let fetch = try await GitHubContributionsService.fetch(username: username, token: token)
            let newSnapshot = ContributionSnapshot.from(fetch.calendar)
            newSnapshot.save()

            AppConfig.authFailed = false
            if let expiry = fetch.tokenExpiry {
                AppConfig.tokenExpiry = expiry
                // A new token means new dates, so the old warnings go.
                await NotificationScheduler(center: SystemNotificationCenter()).removeTokenNotifications()
            }

            // Someone connecting mid-streak isn't congratulated for a
            // milestone they passed before installing the app, and gaps from
            // before today never count as missed.
            if isFirstConnect {
                AppConfig.lastCelebratedStreak = NotificationPlanner.milestoneBaseline(
                    for: newSnapshot, protection: AppConfig.streakProtection, asOf: Date()
                )
                AppConfig.startTracking()
                protection = AppConfig.streakProtection
            }

            await NotificationCoordinator.reconcile(snapshot: newSnapshot)

            snapshot = newSnapshot
            tokenExpiry = AppConfig.tokenExpiry
            status = .success
            WidgetCenter.shared.reloadAllTimelines()
        } catch GitHubServiceError.unauthorized {
            AppConfig.authFailed = true
            await NotificationCoordinator.reconcile()
            status = .failed("GitHub didn't accept that token. It may have expired.")
        } catch GitHubServiceError.userNotFound {
            status = .failed("GitHub has no user named \(username). Check the spelling.")
        } catch GitHubServiceError.rateLimited {
            // Not an auth failure: reminders keep running on the saved data.
            status = .failed("GitHub is busy. Try again in a few minutes.")
        } catch GitHubServiceError.apiError(let message) {
            status = .failed("GitHub returned an error: \(message)")
        } catch {
            status = .failed("Couldn't reach GitHub. Check your connection.")
        }
    }
}
