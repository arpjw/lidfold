import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let store: SettingsStore
    private let launchAtLoginController: LaunchAtLoginController

    init(
        store: SettingsStore = SettingsStore(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.store = store
        self.launchAtLoginController = launchAtLoginController

        switch launchAtLoginController.status {
        case .enabled, .requiresApproval:
            store.setLaunchAtLogin(true)
        case .disabled:
            store.setLaunchAtLogin(false)
        case .unavailable:
            break
        }

        let content = SettingsView(
            store: store,
            launchAtLoginController: launchAtLoginController
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LidFold Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 510, height: 520))
        window.contentMinSize = NSSize(width: 460, height: 480)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        launchAtLoginController.refreshStatus()
        store.setLaunchAtLogin(launchAtLoginController.isRegistered)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Fold threshold") {
                valueSlider(
                    "Activate below",
                    value: Binding(
                        get: { store.activationAngle },
                        set: { store.setActivationAngle($0) }
                    ),
                    range: 5...89,
                    suffix: "°"
                )
                valueSlider(
                    "Deactivate above",
                    value: Binding(
                        get: { store.deactivationAngle },
                        set: { store.setDeactivationAngle($0) }
                    ),
                    range: 6...100,
                    suffix: "°"
                )
                Text("The gap prevents the effect from flickering near the threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                valueSlider(
                    "Maximum blur",
                    value: Binding(
                        get: { store.maximumBlurRadius },
                        set: { store.setMaximumBlurRadius($0) }
                    ),
                    range: 0...40,
                    suffix: " pt"
                )
                valueSlider(
                    "Perspective",
                    value: Binding(
                        get: { store.maximumPerspective },
                        set: { store.setMaximumPerspective($0) }
                    ),
                    range: 0...1
                )
                valueSlider(
                    "Shadow",
                    value: Binding(
                        get: { store.maximumShadowOpacity },
                        set: { store.setMaximumShadowOpacity($0) }
                    ),
                    range: 0...1
                )
                Toggle(
                    "Reduce motion",
                    isOn: Binding(
                        get: { store.reducedMotion },
                        set: { store.setReducedMotion($0) }
                    )
                )
            }

            Section("Startup") {
                Toggle(
                    "Enable the fold effect when LidFold opens",
                    isOn: Binding(
                        get: { store.effectEnabledAtLaunch },
                        set: { store.setEffectEnabledAtLaunch($0) }
                    )
                )
                Toggle("Open LidFold at login", isOn: launchAtLoginBinding)

                if launchAtLoginController.status == .requiresApproval {
                    Text("Allow LidFold in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    store.restoreDefaults()
                    do {
                        try launchAtLoginController.setEnabled(false)
                        launchAtLoginError = nil
                    } catch {
                        store.setLaunchAtLogin(launchAtLoginController.isRegistered)
                        launchAtLoginError = error.localizedDescription
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 460, idealWidth: 510, minHeight: 480, idealHeight: 520)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { enabled in
                do {
                    try launchAtLoginController.setEnabled(enabled)
                    store.setLaunchAtLogin(enabled)
                    launchAtLoginError = nil
                } catch {
                    store.setLaunchAtLogin(launchAtLoginController.isRegistered)
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    @ViewBuilder
    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = ""
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))) + suffix)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }
}
