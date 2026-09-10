import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginService {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    private let service: any LaunchAtLoginService
    @Published private(set) var status: LaunchAtLoginStatus

    init(service: any LaunchAtLoginService = MainAppLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                guard !isRegistered else { return }
                try service.register()
            } else {
                guard isRegistered else { return }
                try service.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            throw error
        }
    }

    func refreshStatus() {
        status = service.status
    }
}

@MainActor
private final class MainAppLoginItemService: LaunchAtLoginService {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
