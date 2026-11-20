import Foundation
import Observation
import WidgetKit

/// Runs the latest action once things go quiet: a new one scheduled within
/// `delay` of the last replaces the one waiting.
@MainActor
final class Debouncer {
    private let delay: Duration
    private var pending: (@MainActor () -> Void)?
    private var task: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    var isPending: Bool { pending != nil }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pending = action
        task?.cancel()
        task = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Runs what's waiting right away, if anything is.
    func flush() {
        task?.cancel()
        task = nil
        let action = pending
        pending = nil
        action?()
    }
}

/// The style library as the app's screens see it. Every change shows at
/// once; saving it and repainting the widgets wait until the taps settle,
/// so a burst of taps costs one save and one widget reload.
@MainActor
@Observable
final class StyleLibraryStore {
    private(set) var library: StyleLibrary

    @ObservationIgnored private let save: (StyleLibrary) -> Void
    @ObservationIgnored private let reload: () -> Void
    @ObservationIgnored private let debouncer: Debouncer

    init(
        library: StyleLibrary = AppConfig.styleLibrary,
        delay: Duration = .milliseconds(500),
        save: @escaping (StyleLibrary) -> Void = StyleLibraryStore.saveToSharedContainer,
        reload: @escaping () -> Void = StyleLibraryStore.reloadWidgets
    ) {
        self.library = library
        self.save = save
        self.reload = reload
        debouncer = Debouncer(delay: delay)
    }

    /// Changes the library on screen now and saves it shortly.
    func update(_ change: (inout StyleLibrary) -> Void) {
        var updated = library
        change(&updated)
        guard updated != library else { return }
        library = updated
        debouncer.schedule { [weak self] in self?.commit() }
    }

    /// Saves and repaints now, for leaving a screen or the app.
    func flush() {
        debouncer.flush()
    }

    /// Picks up what's saved, unless changes of ours are still on the way.
    func refresh() {
        guard !debouncer.isPending else { return }
        // Read behind any save still on the queue, so coming straight back
        // to the app can't load the library from before the last change.
        let saved = Self.queue.sync { AppConfig.styleLibrary }
        if saved != library { library = saved }
    }

    private func commit() {
        save(library)
        reload()
    }

    // MARK: - Off the main thread

    /// One queue, so a reload always follows the save it's for.
    private nonisolated static let queue = DispatchQueue(label: "com.kyreshamwell.pushed.styles", qos: .utility)

    nonisolated static func saveToSharedContainer(_ library: StyleLibrary) {
        queue.async { AppConfig.styleLibrary = library }
    }

    nonisolated static func reloadWidgets() {
        queue.async { WidgetCenter.shared.reloadAllTimelines() }
    }
}
