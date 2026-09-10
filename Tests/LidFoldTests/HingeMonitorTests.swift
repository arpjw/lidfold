import XCTest
@testable import LidFold

final class HingeMonitorTests: XCTestCase {
    func testFilterRejectsMissingAndInvalidReadings() {
        var filter = HingeReadingFilter()

        XCTAssertNil(filter.process(nil))
        XCTAssertNil(filter.process(.nan))
        XCTAssertNil(filter.process(.infinity))
        XCTAssertNil(filter.process(-1))
        XCTAssertNil(filter.process(181))
    }

    func testFilterSmoothsReadings() {
        var filter = HingeReadingFilter(smoothingFactor: 0.25)

        XCTAssertEqual(filter.process(100), 100)
        XCTAssertEqual(filter.process(80), 95)
        XCTAssertEqual(filter.process(80), 91.25)
    }

    func testInvalidReadingClearsSmoothingHistory() {
        var filter = HingeReadingFilter(smoothingFactor: 0.25)

        XCTAssertEqual(filter.process(100), 100)
        XCTAssertEqual(filter.process(80), 95)
        XCTAssertNil(filter.process(nil))
        XCTAssertEqual(filter.process(80), 80)
    }

    func testSampleOnceUsesInjectedReader() async {
        let monitor = HingeMonitor(readAngle: { 72 })

        let angle = await monitor.sampleOnce()

        XCTAssertEqual(angle, 72)
    }
}
