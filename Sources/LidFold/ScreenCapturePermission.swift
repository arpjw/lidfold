import CoreGraphics

/// The result of checking or requesting macOS Screen Recording access.
enum ScreenCapturePermissionStatus: Equatable, Sendable {
    case authorized
    case authorizationRequired
}

/// A small boundary around macOS's process-wide Screen Recording permission APIs.
///
/// Keeping this separate from `SCStream` creation lets the app present permission
/// onboarding before it starts a capture session. The injected operations also make
/// permission-dependent flows testable without showing a system prompt.
struct ScreenCapturePermission: Sendable {
    private let preflightAccess: @Sendable () -> Bool
    private let requestAccess: @Sendable () -> Bool

    init(
        preflightAccess: @escaping @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        requestAccess: @escaping @Sendable () -> Bool = {
            CGRequestScreenCaptureAccess()
        }
    ) {
        self.preflightAccess = preflightAccess
        self.requestAccess = requestAccess
    }

    /// Checks the current authorization without presenting a system prompt.
    func preflight() -> ScreenCapturePermissionStatus {
        Self.status(from: preflightAccess())
    }

    /// Requests access when needed and returns the resulting authorization state.
    ///
    /// Call this from a user-initiated action because macOS may present a consent dialog.
    /// A denied request remains `authorizationRequired`; the caller can then direct the
    /// user to Privacy & Security settings.
    @discardableResult
    func requestAuthorization() -> ScreenCapturePermissionStatus {
        let currentStatus = preflight()
        guard currentStatus != .authorized else { return currentStatus }
        return Self.status(from: requestAccess())
    }

    private static func status(from hasAccess: Bool) -> ScreenCapturePermissionStatus {
        hasAccess ? .authorized : .authorizationRequired
    }
}
