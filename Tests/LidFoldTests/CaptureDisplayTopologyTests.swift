import CoreGraphics
import XCTest

@testable import LidFold

final class CaptureDisplayTopologyTests: XCTestCase {
    func testSelectsBuiltInDisplayInsteadOfExternalMainDisplay() {
        let displays = [
            CaptureDisplayDescriptor(id: 20, isBuiltIn: false, isMain: true),
            CaptureDisplayDescriptor(id: 10, isBuiltIn: true, isMain: false),
        ]

        XCTAssertEqual(CaptureDisplayTopology.preferredDisplayID(in: displays), 10)
    }

    func testPrefersMainBuiltInDisplay() {
        let displays = [
            CaptureDisplayDescriptor(id: 20, isBuiltIn: true, isMain: false),
            CaptureDisplayDescriptor(id: 10, isBuiltIn: true, isMain: true),
        ]

        XCTAssertEqual(CaptureDisplayTopology.preferredDisplayID(in: displays), 10)
    }

    func testSelectionIsStableWhenNoBuiltInDisplayIsMain() {
        let displays = [
            CaptureDisplayDescriptor(id: 20, isBuiltIn: true, isMain: false),
            CaptureDisplayDescriptor(id: 10, isBuiltIn: true, isMain: false),
        ]

        XCTAssertEqual(CaptureDisplayTopology.preferredDisplayID(in: displays), 10)
    }

    func testReturnsNilWithoutBuiltInDisplay() {
        let displays = [
            CaptureDisplayDescriptor(id: 20, isBuiltIn: false, isMain: true)
        ]

        XCTAssertNil(CaptureDisplayTopology.preferredDisplayID(in: displays))
    }
}
