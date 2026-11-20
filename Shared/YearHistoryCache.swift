import Foundation

/// Finished years on disk, one file per year, kept per account.
///
/// A year that's over never changes on GitHub, so each one is fetched once
/// and read from here after that. The year still underway is never stored:
/// it comes from the snapshot, which stays current.
struct YearHistoryCache {
    let directory: URL

    /// In the app group, beside the rest of Pushed's data.
    static var shared: YearHistoryCache {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return YearHistoryCache(directory: base.appendingPathComponent("YearHistory", isDirectory: true))
    }

    private struct Account: Codable {
        var joinYear: Int
    }

    // MARK: - Years

    func year(_ year: Int, for login: String) -> ContributionYear? {
        guard let data = try? Data(contentsOf: fileURL("\(year).json", login: login)),
              let stored = try? JSONDecoder().decode(ContributionYear.self, from: data),
              stored.year == year else { return nil }
        return stored
    }

    /// Stores a year once it's over. The current year, or one still to come,
    /// is turned away, since its numbers are still changing. Returns whether
    /// it was stored.
    @discardableResult
    func save(
        _ data: ContributionYear,
        for login: String,
        asOf now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard data.year < calendar.component(.year, from: now) else { return false }
        return write(data, to: fileURL("\(data.year).json", login: login))
    }

    // MARK: - The account

    /// The year the account was made, the first year worth showing.
    func joinYear(for login: String) -> Int? {
        guard let data = try? Data(contentsOf: fileURL("account.json", login: login)) else { return nil }
        return (try? JSONDecoder().decode(Account.self, from: data))?.joinYear
    }

    func saveJoinYear(_ year: Int, for login: String) {
        write(Account(joinYear: year), to: fileURL("account.json", login: login))
    }

    /// Forgets every account's years, for when GitHub is disconnected.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    /// A folder per login, lowercased since GitHub logins ignore case.
    /// Anything that isn't a letter, digit or hyphen is dropped, so a login
    /// can never reach outside the folder.
    private func fileURL(_ name: String, login: String) -> URL {
        let safe = String(login.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        return directory
            .appendingPathComponent(safe.isEmpty ? "_" : safe, isDirectory: true)
            .appendingPathComponent(name)
    }

    @discardableResult
    private func write<Value: Encodable>(_ value: Value, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
