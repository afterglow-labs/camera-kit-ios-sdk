import XCTest
@testable import SCSDKCameraKitReferenceUI

final class LensLayerStackTests: XCTestCase {
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

    func testResetClearsBothLayers() {
        var stack = LensLayerStack<String>()

        stack.select("retouch", matches: ==)
        XCTAssertTrue(stack.pinCurrent())
        stack.select("comic", matches: ==)
        stack.reset()

        XCTAssertNil(stack.pinnedBase)
        XCTAssertNil(stack.selectedTop)
        XCTAssertTrue(stack.applied.isEmpty)
    }
}
