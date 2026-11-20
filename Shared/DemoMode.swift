#if DEBUG
import Foundation
import WidgetKit

/// Launching with `-PushedDemo` fills the app and the widget with sample data,
/// so every screen can be seen and screenshotted on a simulator with no GitHub
/// account:
///
///     xcrun simctl launch booted com.kyreshamwell.pushed -PushedDemo
///
/// Add `-PushedDemoQuiet 1` to leave today empty (a streak waiting on today),
/// or `2` to leave yesterday empty as well (a streak that just ended), for
/// trying rest days and the freeze.
///
/// Debug builds only. The fake token lives in memory and never reaches the
/// Keychain, and the next launch without the flag clears the sample data.
enum DemoMode {
    static let username = "user-codes"
    private static let activeKey = "debug-demo-mode"
    /// The real rest days and claims, kept aside while the demo's are in use.
    private static let savedProtectionKey = "debug-demo-saved-protection"

    /// Launch arguments given as `-Name value` land in UserDefaults.
    private static var quietDays: Int {
        max(UserDefaults.standard.integer(forKey: "PushedDemoQuiet"), 0)
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-PushedDemo")
    }

    /// The widget extension never sees the app's launch arguments, so the app
    /// leaves it a note in the shared container instead.
    static var isActive: Bool {
        AppConfig.sharedDefaults.bool(forKey: activeKey)
    }

    /// A weekday early this month, so the freeze lands in the month on show.
    private static var freezeDaysAgo: Int {
        let day = Calendar(identifier: .gregorian).component(.day, from: Date())
        return day > 9 ? day - 6 : 3
    }

    private static var sampleProtection: StreakProtection {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let start = calendar.date(byAdding: .day, value: -300, to: today) ?? today
        var protection = StreakProtection.initial
        // Saturday rest days began with this streak, so only its Saturdays show R.
        let restStart = calendar.date(byAdding: .day, value: -42 - quietDays, to: today) ?? today
        protection.schedules = [.init(from: StreakProtection.key(restStart), weekdays: [7])]
        protection.trackedSince = StreakProtection.key(start)
        let frozen = calendar.date(byAdding: .day, value: -freezeDaysAgo - quietDays, to: today) ?? today
        protection.claims[StreakProtection.key(frozen)] = .freeze
        return protection
    }

    static func applyLaunchArguments() {
        let wasActive = isActive
        AppConfig.sharedDefaults.set(isRequested, forKey: activeKey)

        let defaults = AppConfig.sharedDefaults
        if isRequested {
            if !wasActive {
                defaults.set(try? JSONEncoder().encode(AppConfig.streakProtection), forKey: savedProtectionKey)
            }
            AppConfig.streakProtection = sampleProtection
            // Saturdays rest, one freeze this month, and a longer run last
            // summer, so the streak and best streak look like a real habit.
            ContributionSnapshot.sample(
                streak: 41, quiet: quietDays, restWeekday: 6, freezeDaysAgo: freezeDaysAgo,
                bestRun: 58, bestRunEndsDaysAgo: 160
            ).save()
        } else if wasActive {
            // Sample data must not outlive the demo and pass for the real thing.
            defaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
            if let saved = defaults.data(forKey: savedProtectionKey),
               let protection = try? JSONDecoder().decode(StreakProtection.self, from: saved) {
                AppConfig.streakProtection = protection
            }
            defaults.removeObject(forKey: savedProtectionKey)
        }
        if isRequested || wasActive {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
