@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures the built-in display without including LidFold's own windows.
///
/// The engine intentionally supports one stream and one display. Callers should hide any
/// pass-through overlay whenever `onStopped` runs, regardless of whether the optional error
/// is present. This makes both expected stops and ScreenCaptureKit failures fail open.
final class ScreenCaptureEngine: NSObject, @unchecked Sendable {
    /// Core Video buffers are reference-counted and remain valid while this value is retained.
    /// The renderer only reads the buffer after ScreenCaptureKit has delivered it.
    struct CapturedFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
    }

    typealias FrameHandler = @Sendable (CapturedFrame) -> Void
    typealias StopHandler = @Sendable (Error?) -> Void

    enum CaptureError: LocalizedError, Sendable {
        case alreadyRunning
        case applicationNotShareable
        case builtInDisplayUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                "Screen capture is already running."
            case .applicationNotShareable:
                "LidFold could not exclude itself from screen capture."
            case .builtInDisplayUnavailable:
                "No built-in display is available for capture."
            }
        }
    }

    private struct State {
        var isStarting = false
        var stream: SCStream?
        var onFrame: FrameHandler?
        var onStopped: StopHandler?
    }

    private let stateLock = NSLock()
    private let sampleQueue = DispatchQueue(
        label: "org.lidfold.capture.frames",
        qos: .userInteractive
    )
    private var state = State()

    /// Starts capture and returns the Core Graphics identifier of the selected built-in display.
    ///
    /// Only complete frames containing a pixel buffer are delivered. The callback runs on the
    /// engine's serial capture queue, so rendering work should remain bounded and non-blocking.
    @discardableResult
    func start(
        onFrame: @escaping FrameHandler,
        onStopped: @escaping StopHandler
    ) async throws -> CGDirectDisplayID {
        let mayStart = stateLock.withLock {
            guard !state.isStarting, state.stream == nil else { return false }
            state.isStarting = true
            state.onFrame = onFrame
            state.onStopped = onStopped
            return true
        }
        guard mayStart else { throw CaptureError.alreadyRunning }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            guard let application = content.applications.first(where: {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }) else {
                throw CaptureError.applicationNotShareable
            }

            guard let display = content.displays.first(where: {
                CGDisplayIsBuiltin($0.displayID) != 0
            }) else {
                throw CaptureError.builtInDisplayUnavailable
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [application],
                exceptingWindows: []
            )
            let configuration = Self.configuration(for: display)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

            stateLock.withLock {
                state.stream = stream
                state.isStarting = false
            }

            try await stream.startCapture()
            return display.displayID
        } catch {
            finish(with: error)
            throw error
        }
    }

    /// Stops capture. `onStopped(nil)` is delivered exactly once after a normal stop.
    func stop() async {
        let stream = stateLock.withLock { state.stream }
        guard let stream else { return }

        do {
            try await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
            finish(with: nil)
        } catch {
            finish(with: error)
        }
    }

    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    private func finish(with error: Error?) {
        let callback = stateLock.withLock {
            guard state.isStarting || state.stream != nil || state.onStopped != nil else {
                return nil as StopHandler?
            }

            let callback = state.onStopped
            state = State()
            return callback
        }
        callback?(error)
    }
}

extension ScreenCaptureEngine: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let callback = stateLock.withLock { state.onFrame }
        callback?(CapturedFrame(pixelBuffer: pixelBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        try? stream.removeStreamOutput(self, type: .screen)
        finish(with: error)
    }
}
