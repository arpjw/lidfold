import XCTest
@testable import LidFold

final class LidFoldTests: XCTestCase {
    func testDecodesLittleEndianHingeReport() {
        XCTAssertEqual(HingeReport.decode([1, 120, 0]), 120)
        XCTAssertEqual(HingeReport.decode([1, 180, 0]), 180)
    }

    func testRejectsMalformedHingeReports() {
        XCTAssertNil(HingeReport.decode([1, 90]))
        XCTAssertNil(HingeReport.decode([1, 181, 0]))
    }

    func testMapsHingeAngleIntoClampedFoldParameters() {
        XCTAssertEqual(FoldParameters.map(angle: 90).progress, 0)
        XCTAssertEqual(FoldParameters.map(angle: 0).progress, 1)

        let halfway = FoldParameters.map(angle: 43)
        XCTAssertEqual(halfway.progress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(halfway.blurRadius, 9)
    }

    func testReducedMotionKeepsOnlyShading() {
        let parameters = FoldParameters.map(angle: 8, reducedMotion: true)
        XCTAssertEqual(parameters.progress, 0)
        XCTAssertEqual(parameters.perspective, 0)
        XCTAssertEqual(parameters.blurRadius, 0)
        XCTAssertEqual(parameters.shadowOpacity, 0.46)
    }
}
