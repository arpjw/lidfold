import CoreGraphics

/// A stable, testable view of the ScreenCaptureKit display topology.
struct CaptureDisplayDescriptor: Sendable, Equatable {
    let id: CGDirectDisplayID
    let isBuiltIn: Bool
    let isMain: Bool
}

enum CaptureDisplayTopology {
    /// Selects the built-in panel deterministically, preferring it when it is also the main display.
    /// An external main display never displaces the built-in panel.
    static func preferredDisplayID(
        in displays: [CaptureDisplayDescriptor]
    ) -> CGDirectDisplayID? {
        let builtInDisplays = displays.filter(\.isBuiltIn)
        return builtInDisplays.first(where: \.isMain)?.id
            ?? builtInDisplays.min(by: { $0.id < $1.id })?.id
    }
}
