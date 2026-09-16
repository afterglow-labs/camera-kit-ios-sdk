import XCTest
@testable import SCSDKCameraKitReferenceUI

final class LensLayerDisplayTests: XCTestCase {
    func testLayerDisplayNamesDescribeTheAppliedStack() {
        XCTAssertEqual(
            LensLayerDisplay.name(
                persistentBases: ["Retouch", "Nose Adjustments"],
                base: "Face Sculpt",
                top: "Comic"
            ),
            "Retouch + Nose Adjustments + Face Sculpt + Comic"
        )
        XCTAssertEqual(
            LensLayerDisplay.name(persistentBases: ["Retouch", "Nose Adjustments"], base: nil, top: "Comic"),
            "Retouch + Nose Adjustments + Comic"
        )
        XCTAssertEqual(
            LensLayerDisplay.name(persistentBases: ["Retouch", "Nose Adjustments"], base: nil, top: nil),
            "Retouch + Nose Adjustments"
        )
        XCTAssertEqual(LensLayerDisplay.name(base: "Retouch", top: nil), "Retouch (Pinned)")
        XCTAssertEqual(LensLayerDisplay.name(base: "Retouch", top: "Comic"), "Retouch + Comic")
        XCTAssertEqual(LensLayerDisplay.name(base: nil, top: "Comic"), "Comic")
        XCTAssertEqual(LensLayerDisplay.name(base: nil, top: nil), "")
    }

    func testLensIdentityUsesGroupAndID() {
        XCTAssertEqual(
            LensLayerIdentity(id: "1", groupID: "group-a"),
            LensLayerIdentity(id: "1", groupID: "group-a")
        )
        XCTAssertNotEqual(
            LensLayerIdentity(id: "1", groupID: "group-a"),
            LensLayerIdentity(id: "1", groupID: "group-b")
        )
        XCTAssertNotEqual(
            LensLayerIdentity(id: "1", groupID: "group-a"),
            LensLayerIdentity(id: "2", groupID: "group-a")
        )
    }
}
