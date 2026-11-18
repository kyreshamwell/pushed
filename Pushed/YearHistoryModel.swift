import Foundation
import Observation

/// Loads the years for the year sheet: the current one from the snapshot,
/// past ones from the cache or GitHub, and sample years in demo mode.
@MainActor
@Observable
final class YearHistoryModel {
    enum Phase: Equatable {
        case loading
        case loaded(YearSummary)
        case failed(String)
    }

    /// Oldest first, ending with the current year.
    private(set) var years: [Int]
    private(set) var phases: [Int: Phase] = [:]

    private let username: String
    private let token: String
    private let snapshot: ContributionSnapshot?
    private let isDemo: Bool
    private let cache: YearHistoryCache
    private let now: Date
    private let currentYear: Int
    private var inFlight: Set<Int> = []

    /// GitHub opened in 2008, so no account has data before then.
    private static let firstPossibleYear = 2008

    init(
        username: String,
        token: String,
        snapshot: ContributionSnapshot?,
        isDemo: Bool,
        cache: YearHistoryCache = .shared,
        now: Date = Date()
    ) {
        self.username = username
        self.token = token
        self.snapshot = snapshot
        self.isDemo = isDemo
        self.cache = cache
        self.now = now
        currentYear = Calendar(identifier: .gregorian).component(.year, from: now)

        let joinYear = isDemo ? currentYear - ContributionYear.sampleYearsBack : cache.joinYear(for: username)
        years = Self.years(from: joinYear, to: currentYear)
    }

    private static func years(from joinYear: Int?, to current: Int) -> [Int] {
        let first = min(max(joinYear ?? current, firstPossibleYear), current)
        return Array(first...current)
    }

    func phase(for year: Int) -> Phase {
        phases[year] ?? .loading
    }

    /// Finds the join year if it isn't known yet, so the switcher can list
    /// every year. A failure here just leaves the current year on its own.
    func loadYears() async {
        guard !isDemo, cache.joinYear(for: username) == nil, !username.isEmpty, !token.isEmpty else { return }
        guard let joinYear = try? await GitHubContributionsService.fetchJoinYear(username: username, token: token) else { return }
        cache.saveJoinYear(joinYear, for: username)
        years = Self.years(from: joinYear, to: currentYear)
    }

    func load(_ year: Int) async {
        if case .loaded = phases[year] { return }
        guard !inFlight.contains(year) else { return }
        inFlight.insert(year)
        defer { inFlight.remove(year) }

        if let data = localYear(year) {
            phases[year] = .loaded(YearSummary(data, today: now))
            return
        }

        phases[year] = .loading
        do {
            let data = try await GitHubContributionsService.fetchYear(year, username: username, token: token)
            cache.save(data, for: username, asOf: now)
            phases[year] = .loaded(YearSummary(data, today: now))
        } catch {
            phases[year] = .failed(Self.message(for: error))
        }
    }

    /// A year that needs no network: a sample in demo mode, the current year
    /// from the snapshot, or a past year already cached.
    private func localYear(_ year: Int) -> ContributionYear? {
        if isDemo {
            if year == currentYear, let snapshot, let data = ContributionYear(snapshot: snapshot, year: year) {
                return data
            }
            return .sample(year: year, joinYear: years.first ?? year)
        }
        if year == currentYear {
            return snapshot.flatMap { ContributionYear(snapshot: $0, year: year) }
        }
        return cache.year(year, for: username)
    }

    private static func message(for error: Error) -> String {
        switch error as? GitHubServiceError {
        case .unauthorized: "GitHub didn't accept your token."
        case .rateLimited: "GitHub is busy. Try again in a few minutes."
        case .userNotFound: "GitHub couldn't find this account."
        default: "Couldn't reach GitHub. Check your connection."
        }
    }
}
