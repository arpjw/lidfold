import XCTest
@testable import LidFold

final class LaunchAtLoginControllerTests: XCTestCase {
    @MainActor
    func testRegistersAndUnregistersLoginItem() throws {
        let service = FakeLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(controller.isEnabled)

        try controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
    }

    @MainActor
    func testRepeatedRequestIsIdempotent() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    @MainActor
    func testPendingApprovalIsAlreadyRegistered() throws {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertTrue(controller.isRegistered)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .disabled
    }
}
