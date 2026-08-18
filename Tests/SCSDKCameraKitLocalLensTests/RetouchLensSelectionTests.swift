import XCTest
@testable import SCSDKCameraKitReferenceUI

final class RetouchLensSelectionTests: XCTestCase {
    func testPreferredMLVariantIsSelectedWhenBothVariantsExist() {
        let options = RetouchLensOptions(standard: "standard", machineLearning: "ml")

        XCTAssertEqual(options.resolvedVariant(preferred: .machineLearning), .machineLearning)
        XCTAssertEqual(options[.machineLearning], "ml")
        XCTAssertEqual(options.availableVariants, [.standard, .machineLearning])
    }

    func testUnavailablePreferredVariantFallsBackToAvailableVariant() {
        let options = RetouchLensOptions<String>(standard: "standard", machineLearning: nil)

        XCTAssertEqual(options.resolvedVariant(preferred: .machineLearning), .standard)
    }

    func testNoVariantIsSelectedWhenNoRetouchLensExists() {
        let options = RetouchLensOptions<String>(standard: nil, machineLearning: nil)

        XCTAssertNil(options.resolvedVariant(preferred: .standard))
        XCTAssertTrue(options.availableVariants.isEmpty)
    }
}
