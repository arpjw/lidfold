import AppKit

@main
enum LidFoldApp {
    @MainActor
    static func main() {
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
    private let sensor = HingeAngleSensor()
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var isPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.menu = makeMenu()
        statusItem = item

        updateReading()
        updateTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updateReading),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let state = NSMenuItem(title: "Waiting for hinge sensor", action: nil, keyEquivalent: "")
        state.tag = MenuTag.sensorState
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePaused), keyEquivalent: "p")
        pause.tag = MenuTag.pause
        pause.target = self
        menu.addItem(pause)

        let quit = NSMenuItem(title: "Quit LidFold", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func updateReading() {
        guard !isPaused else { return }

        if let angle = sensor.readAngle() {
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
    }

    @objc private func togglePaused() {
        isPaused.toggle()
        statusItem?.menu?.item(withTag: MenuTag.pause)?.title = isPaused ? "Resume" : "Pause"
        statusItem?.button?.appearsDisabled = isPaused
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum MenuTag {
    static let sensorState = 100
    static let pause = 101
}
