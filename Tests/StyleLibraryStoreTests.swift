import XCTest

@MainActor
final class StyleLibraryStoreTests: XCTestCase {
    private var saves: [StyleLibrary] = []
    private var reloads = 0

    private func store(delay: Duration = .milliseconds(60)) -> StyleLibraryStore {
        StyleLibraryStore(
            library: .starting(),
            delay: delay,
            save: { [unowned self] in saves.append($0) },
            reload: { [unowned self] in reloads += 1 }
        )
    }

    func testEveryTapShowsAtOnce() {
        let store = store()
        store.update { $0.toggleRotation(.aurora) }
        XCTAssertTrue(store.library.isInRotation(.aurora))
        XCTAssertTrue(saves.isEmpty, "saving waits for the taps to settle")
        XCTAssertEqual(reloads, 0)
    }

    func testABurstOfTapsSavesAndReloadsOnce() async throws {
        let store = store()
        for style in WidgetStyle.builtIn {
            store.update { $0.toggleRotation(style) }
        }
        store.update { $0.toggleRotation(.ember) }
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(saves.last, store.library, "the save holds the last tap")
        XCTAssertFalse(store.library.isInRotation(.ember))
    }

    func testFlushSavesRightAway() {
        let store = store(delay: .seconds(30))
        store.update { $0.add(named: "Mint") }
        store.flush()
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(reloads, 1)

        store.flush()
        XCTAssertEqual(saves.count, 1, "nothing left to save")
    }

    func testAChangeThatChangesNothingIsntSaved() {
        let store = store()
        store.update { _ in }
        store.flush()
        XCTAssertTrue(saves.isEmpty)
    }
}
