import XCTest
@testable import LidFold

final class ScreenCapturePermissionTests: XCTestCase {
    func testPreflightReportsAuthorizedAccess() {
        let permission = ScreenCapturePermission(
            preflightAccess: { true },
            requestAccess: { false }
        )

        XCTAssertEqual(permission.preflight(), .authorized)
    }

    func testPreflightReportsWhenAuthorizationIsRequired() {
        let permission = ScreenCapturePermission(
            preflightAccess: { false },
            requestAccess: { true }
        )

        XCTAssertEqual(permission.preflight(), .authorizationRequired)
    }

    func testRequestReturnsRequestResultWhenNotAlreadyAuthorized() {
        let granted = ScreenCapturePermission(
            preflightAccess: { false },
            requestAccess: { true }
        )
        let denied = ScreenCapturePermission(
            preflightAccess: { false },
            requestAccess: { false }
        )

        XCTAssertEqual(granted.requestAuthorization(), .authorized)
        XCTAssertEqual(denied.requestAuthorization(), .authorizationRequired)
    }

    func testRequestDoesNotNeedRequestResultWhenAlreadyAuthorized() {
        let permission = ScreenCapturePermission(
            preflightAccess: { true },
            requestAccess: {
                XCTFail("requestAccess should not run after a successful preflight")
                return false
            }
        )

        XCTAssertEqual(permission.requestAuthorization(), .authorized)
    }
}
