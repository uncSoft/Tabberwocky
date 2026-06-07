import XCTest
import AppKit
@testable import Tabberwocky

// Logic-only tests — no windows required. The AppKit-touching paths (apply()) no-op
// cleanly when nothing is registered, so the pure state logic is exercisable here.

@MainActor
final class TabberwockyColorStoreTests: XCTestCase {

    private func freshStore() -> TabberwockyColorStore {
        TabberwockyColorStore(defaults: UserDefaults(suiteName: "tw.tests.\(UUID().uuidString)")!,
                              storageKey: "K")
    }

    func testColorRoundTripsAcrossInstances() {
        let suite = UserDefaults(suiteName: "tw.tests.\(UUID().uuidString)")!
        let url = URL(fileURLWithPath: "/tmp/a.md")

        let writer = TabberwockyColorStore(defaults: suite, storageKey: "K")
        writer.setColor(.systemTeal, for: url, .fill)
        writer.setColor(.systemYellow, for: url, .label)

        // A fresh instance (simulating relaunch) reads the persisted values back.
        let reader = TabberwockyColorStore(defaults: suite, storageKey: "K")
        XCTAssertNotNil(reader.color(for: url, .fill))
        XCTAssertNotNil(reader.color(for: url, .label))
    }

    func testFillAndLabelAreIndependent() {
        let store = freshStore()
        let url = URL(fileURLWithPath: "/tmp/b.md")
        store.setColor(.systemRed, for: url, .fill)
        XCTAssertNotNil(store.color(for: url, .fill))
        XCTAssertNil(store.color(for: url, .label))   // label untouched
    }

    func testClearRemovesColor() {
        let store = freshStore()
        let url = URL(fileURLWithPath: "/tmp/c.md")
        store.setColor(.systemBlue, for: url, .fill)
        store.setColor(nil, for: url, .fill)
        XCTAssertNil(store.color(for: url, .fill))
    }

    func testKeysAreStandardized() {
        let store = freshStore()
        let messy = URL(fileURLWithPath: "/tmp/./d.md")        // non-standardized
        let clean = URL(fileURLWithPath: "/tmp/d.md")
        store.setColor(.systemGreen, for: messy, .fill)
        XCTAssertNotNil(store.color(for: clean, .fill))         // same file resolves
    }
}

@MainActor
final class TabberwockyGroupsTests: XCTestCase {

    func testAddGroupCyclesPaletteColors() {
        let groups = TabberwockyGroups()
        groups.addGroup("A")
        groups.addGroup("B")
        XCTAssertEqual(groups.groups.count, 2)
        XCTAssertNotEqual(groups.groups[0].color, groups.groups[1].color)
    }

    func testAddGroupIsIdempotentByName() {
        let groups = TabberwockyGroups()
        let id1 = groups.addGroup("Docs")
        let id2 = groups.addGroup("Docs")        // same name → same group
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(groups.groups.count, 1)
    }

    func testAssignMovesDocumentBetweenGroups() {
        let groups = TabberwockyGroups()
        let a = groups.addGroup("A")
        let b = groups.addGroup("B")
        let url = URL(fileURLWithPath: "/tmp/x.md")

        groups.assign(url, to: a)
        XCTAssertEqual(groups.count("A"), 1)
        XCTAssertEqual(groups.color(forURL: url), groups.groups[0].color)

        groups.assign(url, to: b)                // reassign
        XCTAssertEqual(groups.count("A"), 0)
        XCTAssertEqual(groups.count("B"), 1)
        XCTAssertEqual(groups.color(forURL: url), groups.groups[1].color)
        _ = b
    }

    func testColorForUnknownURLIsNil() {
        let groups = TabberwockyGroups()
        groups.addGroup("A")
        XCTAssertNil(groups.color(forURL: URL(fileURLWithPath: "/tmp/none.md")))
        XCTAssertNil(groups.color(forURL: nil))
    }
}
