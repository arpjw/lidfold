@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures the built-in display without including LidFold's own windows.
///
/// The engine owns at most one stream. Its lifecycle methods are idempotent: concurrent stop
/// requests join the same stop operation, and a stop requested while startup is in flight cancels
/// startup before the stream is exposed to the caller.
final class ScreenCaptureEngine: NSObject, @unchecked Sendable {
    struct CapturedFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
    }

    typealias FrameHandler = @Sendable (CapturedFrame) -> Void
    typealias StopHandler = @Sendable (Error?) -> Void

    enum LifecycleState: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
    }

    enum RecoveryDisposition: Sendable, Equatable {
        case restart
        case waitForDisplay
        case requestAuthorization
        case remainStopped
    }

    enum CaptureError: LocalizedError, Sendable {
        case alreadyRunning
        case applicationNotShareable
        case builtInDisplayUnavailable
        case startCancelled

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                "Screen capture is already running."
            case .applicationNotShareable:
                "LidFold could not exclude itself from screen capture."
            case .builtInDisplayUnavailable:
                "No built-in display is available for capture."
            case .startCancelled:
                "Screen capture startup was cancelled."
            }
        }
    }

    private struct State {
        var lifecycle = LifecycleState.idle
        var generation: UInt64 = 0
        var stream: SCStream?
        var stopRequested = false
        var didStart = false
        var onFrame: FrameHandler?
        var onStopped: StopHandler?
        var stopWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let stateLock = NSLock()
    private let sampleQueue = DispatchQueue(
        label: "org.lidfold.capture.frames",
        qos: .userInteractive
    )
    private var state = State()

    var lifecycleState: LifecycleState {
        stateLock.withLock { state.lifecycle }
    }

    @discardableResult
    func start(
        onFrame: @escaping FrameHandler,
        onStopped: @escaping StopHandler
    ) async throws -> CGDirectDisplayID {
        let generation = try beginStart(onFrame: onFrame, onStopped: onStopped)
        var candidateStream: SCStream?

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            try ensureStartMayContinue(generation: generation)

            let processID = ProcessInfo.processInfo.processIdentifier
            guard
                let application = content.applications.first(where: {
                    $0.processID == processID
                })
            else {
                throw CaptureError.applicationNotShareable
            }

            let descriptors = content.displays.map {
                CaptureDisplayDescriptor(
                    id: $0.displayID,
                    isBuiltIn: CGDisplayIsBuiltin($0.displayID) != 0,
                    isMain: CGDisplayIsMain($0.displayID) != 0
                )
            }
            guard let displayID = CaptureDisplayTopology.preferredDisplayID(in: descriptors),
                let display = content.displays.first(where: { $0.displayID == displayID })
            else {
                throw CaptureError.builtInDisplayUnavailable
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [application],
                exceptingWindows: []
            )
            let stream = SCStream(
                filter: filter,
                configuration: Self.configuration(for: display),
                delegate: self
            )
            candidateStream = stream
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try install(stream: stream, generation: generation)

            try await stream.startCapture()

            if markRunningUnlessStopped(generation: generation) {
                try? await stream.stopCapture()
                try? stream.removeStreamOutput(self, type: .screen)
                complete(generation: generation, error: nil, notify: false)
                throw CaptureError.startCancelled
            }

            return display.displayID
        } catch {
            if let candidateStream {
                try? candidateStream.removeStreamOutput(self, type: .screen)
            }
            complete(generation: generation, error: error, notify: false)
            throw error
        }
    }

    /// Stops capture and waits until its resources have been detached.
    func stop() async {
        switch requestStop() {
        case .done:
            return
        case .wait:
            await waitUntilStopped()
        case .perform(let stream, let generation):
            let error: Error?
            do {
                try await stream.stopCapture()
                error = nil
            } catch let stopError {
                error = stopError
            }
            try? stream.removeStreamOutput(self, type: .screen)
            complete(generation: generation, error: error, notify: true)
        }
    }

    /// Re-resolves the built-in display and starts a fresh stream after wake/topology changes.
    @discardableResult
    func restart(
        onFrame: @escaping FrameHandler,
        onStopped: @escaping StopHandler
    ) async throws -> CGDirectDisplayID {
        await stop()
        return try await start(onFrame: onFrame, onStopped: onStopped)
    }

    static func recoveryDisposition(for error: Error?) -> RecoveryDisposition {
        guard let error else { return .remainStopped }

        if let captureError = error as? CaptureError {
            switch captureError {
            case .builtInDisplayUnavailable:
                return .waitForDisplay
            case .alreadyRunning, .applicationNotShareable, .startCancelled:
                return .remainStopped
            }
        }

        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return .remainStopped }

        switch SCStreamError.Code(rawValue: nsError.code) {
        case .userDeclined:
            return .requestAuthorization
        case .noCaptureSource:
            return .waitForDisplay
        case .systemStoppedStream, .failedToStart:
            return .restart
        default:
            return .remainStopped
        }
    }

    private enum StopRequest {
        case done
        case wait
        case perform(SCStream, UInt64)
    }

    private func beginStart(
        onFrame: @escaping FrameHandler,
        onStopped: @escaping StopHandler
    ) throws -> UInt64 {
        try stateLock.withLock {
            guard state.lifecycle == .idle else { throw CaptureError.alreadyRunning }
            state.generation &+= 1
            state.lifecycle = .starting
            state.stopRequested = false
            state.didStart = false
            state.onFrame = onFrame
            state.onStopped = onStopped
            return state.generation
        }
    }

    private func ensureStartMayContinue(generation: UInt64) throws {
        let mayContinue = stateLock.withLock {
            state.generation == generation
                && state.lifecycle == .starting
                && !state.stopRequested
        }
        guard mayContinue else { throw CaptureError.startCancelled }
    }

    private func install(stream: SCStream, generation: UInt64) throws {
        let installed = stateLock.withLock {
            guard state.generation == generation,
                state.lifecycle == .starting,
                !state.stopRequested
            else { return false }
            state.stream = stream
            return true
        }
        guard installed else { throw CaptureError.startCancelled }
    }

    /// Returns true when startup completed but a stop had already been requested.
    private func markRunningUnlessStopped(generation: UInt64) -> Bool {
        stateLock.withLock {
            guard state.generation == generation, state.lifecycle == .starting else {
                return true
            }
            if state.stopRequested {
                state.lifecycle = .stopping
                return true
            }
            state.lifecycle = .running
            state.didStart = true
            return false
        }
    }

    private func requestStop() -> StopRequest {
        stateLock.withLock {
            switch state.lifecycle {
            case .idle:
                return .done
            case .starting:
                state.stopRequested = true
                return .wait
            case .stopping:
                return .wait
            case .running:
                guard let stream = state.stream else { return .wait }
                state.lifecycle = .stopping
                return .perform(stream, state.generation)
            }
        }
    }

    private func waitUntilStopped() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = stateLock.withLock {
                if state.lifecycle == .idle {
                    return true
                }
                state.stopWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        // Only the newest desktop state matters. One surface prevents stale frames from queuing.
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    private func complete(generation: UInt64, error: Error?, notify: Bool) {
        let completion = stateLock.withLock {
            guard state.generation == generation, state.lifecycle != .idle else {
                return (nil as StopHandler?, [CheckedContinuation<Void, Never>]())
            }

            let callback = notify && state.didStart ? state.onStopped : nil
            let waiters = state.stopWaiters
            let nextGeneration = state.generation
            state = State(generation: nextGeneration)
            return (callback, waiters)
        }
        completion.0?(error)
        completion.1.forEach { $0.resume() }
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

        let callback = stateLock.withLock {
            state.lifecycle == .running ? state.onFrame : nil
        }
        callback?(CapturedFrame(pixelBuffer: pixelBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        try? stream.removeStreamOutput(self, type: .screen)
        let completion = stateLock.withLock { () -> (UInt64, Bool)? in
            guard state.stream === stream, state.lifecycle != .idle else { return nil }
            return (state.generation, state.didStart)
        }
        if let completion {
            complete(generation: completion.0, error: error, notify: completion.1)
        }
    }
}
