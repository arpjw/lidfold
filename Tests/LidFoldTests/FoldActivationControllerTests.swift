import XCTest
@testable import LidFold

@MainActor
final class FoldActivationControllerTests: XCTestCase {
    func testActivatesAndDeactivatesAcrossHysteresisThresholds() {
        let controller = FoldActivationController()

        XCTAssertFalse(controller.update(angle: 78))
        XCTAssertTrue(controller.update(angle: 75.9))
        XCTAssertTrue(controller.update(angle: 79))
        XCTAssertTrue(controller.update(angle: 80))
        XCTAssertFalse(controller.update(angle: 80.1))
    }

    func testMissingOrInvalidReadingAlwaysDeactivates() {
        let controller = FoldActivationController()

        XCTAssertTrue(controller.update(angle: 70))
        XCTAssertFalse(controller.update(angle: nil))

        XCTAssertTrue(controller.update(angle: 70))
        XCTAssertFalse(controller.update(angle: .nan))

        XCTAssertTrue(controller.update(angle: 70))
        XCTAssertFalse(controller.update(angle: 181))
    }

    func testExplicitDeactivateClearsActiveState() {
        let controller = FoldActivationController()
        XCTAssertTrue(controller.update(angle: 70))

        controller.deactivate()

        XCTAssertFalse(controller.isActive)
    }
}
