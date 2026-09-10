import Foundation
import ScreenCaptureKit
import XCTest

@testable import LidFold

final class ScreenCaptureRecoveryTests: XCTestCase {
    func testClassifiesNormalStopAsIntentional() {
        XCTAssertEqual(ScreenCaptureEngine.recoveryDisposition(for: nil), .remainStopped)
    }

    func testWaitsForBuiltInDisplayToReturn() {
        XCTAssertEqual(
            ScreenCaptureEngine.recoveryDisposition(
                for: ScreenCaptureEngine.CaptureError.builtInDisplayUnavailable
            ),
            .waitForDisplay
        )
    }

    func testDoesNotRestartAfterCancelledStartup() {
        XCTAssertEqual(
            ScreenCaptureEngine.recoveryDisposition(
                for: ScreenCaptureEngine.CaptureError.startCancelled
            ),
            .remainStopped
        )
    }

    func testStopIsIdempotentWhenIdle() async {
        let engine = ScreenCaptureEngine()

        await engine.stop()
        await engine.stop()

        XCTAssertEqual(engine.lifecycleState, .idle)
    }

    func testRecognizesPermissionFailure() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userDeclined.rawValue
        )

        XCTAssertEqual(ScreenCaptureEngine.recoveryDisposition(for: error), .requestAuthorization)
    }

    func testDoesNotLoopOnUnknownErrors() {
        let error = NSError(domain: "org.lidfold.tests", code: 1)
        XCTAssertEqual(ScreenCaptureEngine.recoveryDisposition(for: error), .remainStopped)
    }
}
