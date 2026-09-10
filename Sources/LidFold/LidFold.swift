import AppKit
import CoreVideo
import Darwin

@main
enum LidFoldApp {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--capture-smoke-test") {
            do {
                let dimensions = try await captureOneFrame()
                print("Captured a complete BGRA frame: \(dimensions.width)×\(dimensions.height).")
            } catch {
                fputs("Capture smoke test failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--capture-status") {
            switch ScreenCapturePermission().preflight() {
            case .authorized:
                print("Screen Recording permission is authorized.")
            case .authorizationRequired:
                print("Screen Recording permission is not authorized.")
            }
            return
        }

        if CommandLine.arguments.contains("--validate-renderer") {
            do {
                _ = try OverlayController()
                print("Metal renderer initialized successfully.")
            } catch {
                fputs("Renderer validation failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--diagnose") {
            if let angle = HingeAngleSensor().readAngle() {
                print(String(format: "Compatible hinge sensor found: %.1f°", angle))
            } else {
                print("No compatible hinge sensor found.")
            }
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    @MainActor
    private static func captureOneFrame() async throws -> (width: Int, height: Int) {
        let engine = ScreenCaptureEngine()
        let gate = FirstFrameGate()
        let discoveryOverlay = try OverlayController()
        discoveryOverlay.prepareForCaptureDiscovery()

        do {
            _ = try await engine.start(
                onFrame: { frame in
                    Task { await gate.receive(frame) }
                },
                onStopped: { error in
                    Task { await gate.stop(error: error) }
                }
            )
            discoveryOverlay.hide()

            let frame = try await withThrowingTaskGroup(
                of: ScreenCaptureEngine.CapturedFrame.self
            ) { group in
                group.addTask { try await gate.wait() }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw CaptureSmokeTestError.timedOut
                }
                guard let first = try await group.next() else {
                    throw CaptureSmokeTestError.noFrame
                }
                group.cancelAll()
                return first
            }

            await engine.stop()
            let pixelBuffer = frame.pixelBuffer
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
                throw CaptureSmokeTestError.unexpectedPixelFormat
            }
            guard discoveryOverlay.validateFrame(
                pixelBuffer: pixelBuffer,
                parameters: .map(angle: 45)
            ) else {
                throw CaptureSmokeTestError.rendererRejectedFrame
            }
            return (CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))
        } catch {
            discoveryOverlay.hide()
            await engine.stop()
            throw error
        }
    }
}

private enum CaptureSmokeTestError: LocalizedError {
    case noFrame
    case stoppedBeforeFirstFrame(Error?)
    case timedOut
    case unexpectedPixelFormat
    case rendererRejectedFrame

    var errorDescription: String? {
        switch self {
        case .noFrame:
            "Screen capture ended without producing a frame."
        case let .stoppedBeforeFirstFrame(error):
            error?.localizedDescription ?? "Screen capture stopped before its first frame."
        case .timedOut:
            "Screen capture did not produce a frame within eight seconds."
        case .unexpectedPixelFormat:
            "Screen capture produced a frame that was not BGRA."
        case .rendererRejectedFrame:
            "Metal could not bind the captured frame as a texture."
        }
    }
}

private actor FirstFrameGate {
    private var result: Result<ScreenCaptureEngine.CapturedFrame, Error>?
    private var continuation: CheckedContinuation<ScreenCaptureEngine.CapturedFrame, Error>?

    func wait() async throws -> ScreenCaptureEngine.CapturedFrame {
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func receive(_ frame: ScreenCaptureEngine.CapturedFrame) {
        resolve(.success(frame))
    }

    func stop(error: Error?) {
        resolve(.failure(CaptureSmokeTestError.stoppedBeforeFirstFrame(error)))
    }

    private func resolve(_ value: Result<ScreenCaptureEngine.CapturedFrame, Error>) {
        guard result == nil else { return }
        result = value
        continuation?.resume(with: value)
        continuation = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capturePermission = ScreenCapturePermission()
    private let captureEngine = ScreenCaptureEngine()
    private let hingeMonitor = HingeMonitor()
    private let settingsStore = SettingsStore()
    private lazy var settingsWindowController = SettingsWindowController(store: settingsStore)
    private lazy var activationController = FoldActivationController(
        activationAngle: settingsStore.activationAngle,
        deactivationAngle: settingsStore.deactivationAngle
    )

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayController?
    private var effectEnabled = false
    private var isPaused = false
    private var shouldDisplayOverlay = false
    private var currentFoldParameters = FoldParameters.map(angle: 180)
    private var recoveryPending = false
    private var recoveryAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.menu = makeMenu()
        statusItem = item

        do {
            overlayController = try OverlayController()
        } catch {
            setEffectStatus(error.localizedDescription)
            statusItem?.menu?.item(withTag: MenuTag.toggleEffect)?.isEnabled = false
        }

        observeFailOpenEvents()
        Task {
            await hingeMonitor.start { [weak self] angle in
                self?.handleHingeReading(angle)
            }
        }

        if settingsStore.effectEnabledAtLaunch {
            enableEffect(requestAuthorization: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.hide()
        Task {
            await hingeMonitor.stop()
            await captureEngine.stop()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let state = NSMenuItem(title: "Waiting for hinge sensor", action: nil, keyEquivalent: "")
        state.tag = MenuTag.sensorState
        state.isEnabled = false
        menu.addItem(state)

        let effectState = NSMenuItem(title: "Desktop fold is off", action: nil, keyEquivalent: "")
        effectState.tag = MenuTag.effectState
        effectState.isEnabled = false
        menu.addItem(effectState)
        menu.addItem(.separator())

        let toggleEffect = NSMenuItem(
            title: "Enable Desktop Fold",
            action: #selector(toggleEffect),
            keyEquivalent: "e"
        )
        toggleEffect.tag = MenuTag.toggleEffect
        toggleEffect.target = self
        menu.addItem(toggleEffect)

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePaused), keyEquivalent: "p")
        pause.tag = MenuTag.pause
        pause.target = self
        pause.isEnabled = false
        menu.addItem(pause)

        let preferences = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        preferences.target = self
        menu.addItem(preferences)

        let settings = NSMenuItem(
            title: "Open Screen Recording Settings…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        settings.tag = MenuTag.screenRecordingSettings
        settings.target = self
        settings.isHidden = true
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LidFold", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func handleHingeReading(_ angle: Double?) {
        if let angle {
            statusItem?.button?.title = String(format: "⌁ %.0f°", angle)
            statusItem?.menu?.item(withTag: MenuTag.sensorState)?.title = String(
                format: "Hinge angle: %.1f°",
                angle
            )
        } else {
            statusItem?.button?.title = "⌁ --°"
            statusItem?.menu?.item(withTag: MenuTag.sensorState)?.title =
                "No compatible hinge sensor found"
        }

        if activationController.activationAngle != settingsStore.activationAngle
            || activationController.deactivationAngle != settingsStore.deactivationAngle
        {
            activationController = FoldActivationController(
                activationAngle: settingsStore.activationAngle,
                deactivationAngle: settingsStore.deactivationAngle
            )
        }

        let isFoldActive = activationController.update(angle: angle)
        currentFoldParameters = FoldParameters.map(
            angle: angle ?? 180,
            clearAt: settingsStore.deactivationAngle,
            maximumPerspective: settingsStore.maximumPerspective,
            maximumBlurRadius: settingsStore.maximumBlurRadius,
            maximumShadowOpacity: settingsStore.maximumShadowOpacity,
            reducedMotion: settingsStore.reducedMotion
        )
        shouldDisplayOverlay = effectEnabled && !isPaused && isFoldActive
        if !shouldDisplayOverlay {
            overlayController?.hide()
        }
    }

    @objc private func toggleEffect() {
        if effectEnabled {
            disableEffect(status: "Desktop fold is off")
        } else {
            enableEffect(requestAuthorization: true)
        }
    }

    private func enableEffect(requestAuthorization: Bool) {
        guard overlayController != nil else { return }

        let permission = requestAuthorization
            ? capturePermission.requestAuthorization()
            : capturePermission.preflight()
        guard permission == .authorized else {
            setEffectStatus("Screen Recording permission is required")
            statusItem?.menu?.item(withTag: MenuTag.screenRecordingSettings)?.isHidden = false
            return
        }

        setEffectControls(enabled: true)
        setEffectStatus("Starting desktop capture…")
        startCapture()
    }

    private func startCapture() {
        overlayController?.prepareForCaptureDiscovery()
        Task {
            do {
                _ = try await captureEngine.start(
                    onFrame: { [weak self] frame in
                        Task { @MainActor [weak self] in
                            guard let self, self.shouldDisplayOverlay else { return }
                            self.recoveryAttempts = 0
                            self.overlayController?.display(
                                pixelBuffer: frame.pixelBuffer,
                                parameters: self.currentFoldParameters
                            )
                        }
                    },
                    onStopped: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.captureDidStop(error: error)
                        }
                    }
                )
                overlayController?.hide()
                recoveryPending = false
                setEffectStatus("Ready — lower the lid to preview")
            } catch {
                overlayController?.hide()
                captureDidStop(error: error)
            }
        }
    }

    private func disableEffect(status: String) {
        recoveryPending = false
        recoveryAttempts = 0
        setEffectControls(enabled: false)
        activationController.deactivate()
        shouldDisplayOverlay = false
        overlayController?.hide()
        setEffectStatus(status)
        Task { await captureEngine.stop() }
    }

    private func captureDidStop(error: Error?) {
        guard effectEnabled else { return }
        overlayController?.hide()
        shouldDisplayOverlay = false

        if recoveryPending {
            return
        }

        switch ScreenCaptureEngine.recoveryDisposition(for: error) {
        case .restart where recoveryAttempts < 3:
            recoveryAttempts += 1
            restartCapture(status: "Recovering desktop capture…")
        case .waitForDisplay:
            recoveryPending = true
            setEffectStatus("Waiting for the built-in display…")
        case .requestAuthorization:
            statusItem?.menu?.item(withTag: MenuTag.screenRecordingSettings)?.isHidden = false
            disableEffect(status: "Screen Recording permission is required")
        case .restart, .remainStopped:
            disableEffect(status: error?.localizedDescription ?? "Desktop capture stopped")
        }
    }

    private func restartCapture(status: String) {
        recoveryPending = true
        shouldDisplayOverlay = false
        overlayController?.hide()
        setEffectStatus(status)
        Task {
            await captureEngine.stop()
            guard effectEnabled else { return }
            recoveryPending = false
            startCapture()
        }
    }

    private func setEffectControls(enabled: Bool) {
        effectEnabled = enabled
        isPaused = false
        statusItem?.menu?.item(withTag: MenuTag.toggleEffect)?.title =
            enabled ? "Disable Desktop Fold" : "Enable Desktop Fold"
        statusItem?.menu?.item(withTag: MenuTag.pause)?.isEnabled = enabled
        statusItem?.menu?.item(withTag: MenuTag.pause)?.title = "Pause"
        statusItem?.button?.appearsDisabled = false
    }

    private func setEffectStatus(_ title: String) {
        statusItem?.menu?.item(withTag: MenuTag.effectState)?.title = title
    }

    @objc private func togglePaused() {
        guard effectEnabled else { return }
        isPaused.toggle()
        statusItem?.menu?.item(withTag: MenuTag.pause)?.title = isPaused ? "Resume" : "Pause"
        statusItem?.button?.appearsDisabled = isPaused
        if isPaused {
            shouldDisplayOverlay = false
            overlayController?.hide()
            setEffectStatus("Desktop fold is paused")
        } else {
            shouldDisplayOverlay = activationController.isActive
            setEffectStatus("Ready — lower the lid to preview")
        }
    }

    private func observeFailOpenEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(suspendForSystemChange),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(suspendForSystemChange),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(resumeAfterSystemChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(resumeAfterSystemChange),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restartAfterDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func suspendForSystemChange(_ notification: Notification) {
        overlayController?.hide()
        shouldDisplayOverlay = false
        guard effectEnabled else { return }
        recoveryPending = true
        setEffectStatus("Desktop capture suspended…")
        Task { await captureEngine.stop() }
    }

    @objc private func resumeAfterSystemChange(_ notification: Notification) {
        guard effectEnabled, recoveryPending else { return }
        restartCapture(status: "Restoring desktop capture…")
    }

    @objc private func restartAfterDisplayChange(_ notification: Notification) {
        guard effectEnabled else {
            overlayController?.hide()
            return
        }
        restartCapture(status: "Updating for display changes…")
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum MenuTag {
    static let sensorState = 100
    static let effectState = 101
    static let toggleEffect = 102
    static let pause = 103
    static let screenRecordingSettings = 104
}
