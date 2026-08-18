import XCTest
@testable import SCSDKCameraKitReferenceUI

final class LensLayerStackTests: XCTestCase {
    func testPersistentControlsStackWithPinnedBaseAndSelectedTop() {
        var stack = LensLayerStack<String>()

        stack.setPersistentBases(["retouch", "rhinoplasty"])
        stack.select("face-sculpt", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)

        XCTAssertEqual(stack.applied, ["retouch", "rhinoplasty", "face-sculpt", "comic"])
        XCTAssertEqual(stack.current, "comic")

        stack.clearTop()
        XCTAssertEqual(stack.applied, ["retouch", "rhinoplasty", "face-sculpt"])

        stack.unpin()
        XCTAssertEqual(stack.applied, ["retouch", "rhinoplasty"])
        XCTAssertNil(stack.current)
    }

    func testPinApplyReplaceClearAndUnpinTransitions() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        XCTAssertEqual(stack.applied, ["retouch"])

        stack.select("comic", matches: ==)
        XCTAssertEqual(stack.applied, ["retouch", "comic"])

        stack.select("neon", matches: ==)
        XCTAssertEqual(stack.applied, ["retouch", "neon"])

        stack.clearTop()
        XCTAssertEqual(stack.applied, ["retouch"])

        stack.select("comic", matches: ==)
        stack.unpin()
        XCTAssertNil(stack.pinnedBase)
        XCTAssertEqual(stack.applied, ["comic"])
    }

    func testSelectingPinnedBaseClearsTopWithoutDuplicatingBase() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)
        stack.select("retouch", matches: ==)

        XCTAssertEqual(stack.applied, ["retouch"])
        XCTAssertEqual(stack.current, "retouch")
    }

    func testUnpinningBaseOnlyClearsStack() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.unpin()

        XCTAssertTrue(stack.applied.isEmpty)
        XCTAssertNil(stack.current)
    }

    func testRemovingBasePromotesTopToSoleSelection() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)
        stack.remove(where: { $0 == "retouch" })

        XCTAssertNil(stack.pinnedBase)
        XCTAssertEqual(stack.applied, ["comic"])
        XCTAssertEqual(stack.current, "comic")
    }

    func testRemovingTopKeepsPinnedBase() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)
        stack.remove(where: { $0 == "comic" })

        XCTAssertEqual(stack.pinnedBase, "retouch")
        XCTAssertEqual(stack.applied, ["retouch"])
        XCTAssertEqual(stack.current, "retouch")
    }

    func testPinRequiresAnUnpinnedCurrentSelection() {
        var stack = LensLayerStack<String>()

        XCTAssertFalse(stack.pinCurrent())
        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        XCTAssertFalse(stack.pinCurrent())
    }

    func testReplacingBasePromotesCurrentTopAndRemovesPreviousBase() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)

        XCTAssertTrue(stack.replaceBaseWithCurrent())
        XCTAssertEqual(stack.pinnedBase, "comic")
        XCTAssertNil(stack.selectedTop)
        XCTAssertEqual(stack.applied, ["comic"])
    }

    func testResetClearsEveryLayer() {
        var stack = LensLayerStack<String>()

        stack.setPersistentBases(["persistent-retouch", "persistent-rhinoplasty"])
        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)
        stack.reset()

        XCTAssertTrue(stack.persistentBases.isEmpty)
        XCTAssertNil(stack.pinnedBase)
        XCTAssertNil(stack.selectedTop)
        XCTAssertTrue(stack.applied.isEmpty)
    }
}
