import AppKit
import CoreGraphics
import CoreVideo
import Metal
import MetalKit

@MainActor
final class OverlayController {
    enum OverlayError: LocalizedError {
        case builtInDisplayUnavailable
        case metalUnavailable

        var errorDescription: String? {
            switch self {
            case .builtInDisplayUnavailable:
                "The built-in display is not currently available."
            case .metalUnavailable:
                "Metal is not available on this Mac."
            }
        }
    }

    private let panel: OverlayPanel
    private let metalView: MTKView
    private let renderer: FoldRenderer

    private(set) var isVisible = false

    init(screen requestedScreen: NSScreen? = nil) throws {
        guard let screen = requestedScreen ?? Self.builtInScreen() else {
            throw OverlayError.builtInDisplayUnavailable
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OverlayError.metalUnavailable
        }

        let renderer = try FoldRenderer(device: device)
        let metalView = MTKView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            device: device
        )
        metalView.autoresizingMask = [.width, .height]
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.delegate = renderer

        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.title = "LidFold Overlay"
        panel.contentView = metalView
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.orderOut(nil)

        self.panel = panel
        self.metalView = metalView
        self.renderer = renderer
    }

    /// Makes this process discoverable to ScreenCaptureKit without showing pixels.
    /// The transparent, click-through panel is ordered in only long enough for the
    /// capture filter to resolve and exclude LidFold's running application.
    func prepareForCaptureDiscovery() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
    }

    /// Presents a complete captured frame. Invalid frames immediately fail open.
    func display(pixelBuffer: CVPixelBuffer, parameters: FoldParameters) {
        guard renderer.update(pixelBuffer: pixelBuffer, parameters: parameters) else {
            hide()
            return
        }

        if !isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            isVisible = true
        }
        metalView.setNeedsDisplay(metalView.bounds)
    }

    /// Validates the zero-copy Core Video to Metal bridge without presenting the panel.
    func validateFrame(pixelBuffer: CVPixelBuffer, parameters: FoldParameters) -> Bool {
        let accepted = renderer.update(pixelBuffer: pixelBuffer, parameters: parameters)
        renderer.clearFrame()
        return accepted
    }

    /// Removes the overlay and releases the last captured surface.
    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 1
        renderer.clearFrame()
        isVisible = false
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
            else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
