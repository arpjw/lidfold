import AppKit
import Darwin

@main
enum LidFoldApp {
    @MainActor
    static func main() {
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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capturePermission = ScreenCapturePermission()
    private let captureEngine = ScreenCaptureEngine()
    private let hingeMonitor = HingeMonitor()
    private let activationController = FoldActivationController()

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayController?
    private var effectEnabled = false
    private var isPaused = false
    private var shouldDisplayOverlay = false
    private var currentFoldParameters = FoldParameters.map(angle: 180)

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

        let isFoldActive = activationController.update(angle: angle)
        currentFoldParameters = FoldParameters.map(angle: angle ?? 180)
        shouldDisplayOverlay = effectEnabled && !isPaused && isFoldActive
        if !shouldDisplayOverlay {
            overlayController?.hide()
        }
    }

    @objc private func toggleEffect() {
        if effectEnabled {
            disableEffect(status: "Desktop fold is off")
        } else {
            enableEffect()
        }
    }

    private func enableEffect() {
        guard overlayController != nil else { return }

        let permission = capturePermission.requestAuthorization()
        guard permission == .authorized else {
            setEffectStatus("Screen Recording permission is required")
            statusItem?.menu?.item(withTag: MenuTag.screenRecordingSettings)?.isHidden = false
            return
        }

        setEffectControls(enabled: true)
        setEffectStatus("Starting desktop capture…")

        Task {
            do {
                _ = try await captureEngine.start(
                    onFrame: { [weak self] frame in
                        Task { @MainActor [weak self] in
                            guard let self, self.shouldDisplayOverlay else { return }
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
                setEffectStatus("Ready — lower the lid to preview")
            } catch {
                captureDidStop(error: error)
            }
        }
    }

    private func disableEffect(status: String) {
        setEffectControls(enabled: false)
        activationController.deactivate()
        shouldDisplayOverlay = false
        overlayController?.hide()
        setEffectStatus(status)
        Task { await captureEngine.stop() }
    }

    private func captureDidStop(error: Error?) {
        guard effectEnabled else { return }
        disableEffect(status: error?.localizedDescription ?? "Desktop capture stopped")
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
            selector: #selector(failOpenForSystemChange),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(failOpenForSystemChange),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(failOpenForSystemChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func failOpenForSystemChange(_ notification: Notification) {
        guard effectEnabled else {
            overlayController?.hide()
            return
        }
        disableEffect(status: "Disabled after a system or display change")
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
