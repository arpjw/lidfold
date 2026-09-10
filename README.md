# LidFold

LidFold is a free, open-source macOS experiment that makes the desktop visually fold as a
MacBook lid closes. The project is a clean-room implementation inspired by the interaction,
not the branding, code, copy, or assets of any commercial app.

The current prototype reads the hinge angle, captures the built-in display with
ScreenCaptureKit, and renders a GPU-accelerated fold through a click-through Metal overlay.
It fails open by hiding the overlay whenever capture, sleep, session, or display state changes.

## Status

- [x] Native menu-bar app
- [x] Live hinge-angle reader
- [x] Tested angle-to-effect mapping
- [x] Smoothed hinge monitoring and activation hysteresis
- [x] Screen Recording permission boundary
- [x] Screen Recording menu onboarding
- [x] Built-in-display ScreenCaptureKit stream
- [x] Metal perspective, blur, shade, and shadow prototype
- [x] Sleep, session, capture, and display-change recovery
- [x] Settings window and launch at login
- [x] Universal ad-hoc-signed app ZIP and DMG automation
- [ ] Developer ID-signed and notarized release

## Requirements

- macOS 14 or newer
- An Apple silicon MacBook with the lid-orientation HID sensor
- Swift 6.2 or newer for command-line builds
- Full Xcode for universal release packaging, Developer ID signing, and notarization

The lid sensor is not a public Apple API. LidFold reads an undocumented HID feature report,
so hardware and future macOS compatibility are not guaranteed. The desktop effect requires
Screen Recording permission, but frames remain on-device.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/arpjw/lidfold/releases), open
it, and drag LidFold into Applications. Launch LidFold, use its menu-bar icon to enable the
effect, and approve Screen Recording when macOS asks.

Until releases have a Developer ID signature, macOS may block the first launch. Control-click
LidFold in Applications, choose **Open**, then confirm **Open**. This uses macOS's standard
per-app override without disabling Gatekeeper globally.

## Build and run

```sh
swift build
swift run LidFold --diagnose
swift run LidFold --capture-status
swift run LidFold --capture-smoke-test
swift run LidFold --validate-renderer
swift run LidFold
```

`swift run LidFold` launches a menu-bar-only process. Quit it from the menu-bar menu.
Run `swift test` after selecting a full Xcode installation; Apple's standalone Command Line
Tools SDK does not include the XCTest module.

For a development app bundle:

```sh
scripts/build-app.sh
open dist/LidFold.app
```

For a universal ad-hoc-signed ZIP and DMG, select a full Xcode installation and run:

```sh
VERSION=0.1.0 scripts/package-release.sh
```

## Continuous integration and releases

GitHub Actions builds both the Swift package and native Xcode app and runs every unit test on
macOS with Xcode 26.3. Version tags matching `v*` create a GitHub release containing a universal
ad-hoc-signed app ZIP, DMG, source archive, and SHA-256 checksums. Builds remain available without
an Apple account; the final Developer ID signing and notarization step can be enabled once
maintainer credentials are configured. Until then, macOS may require users to Control-click the
app, choose **Open**, and confirm the first launch.

Signing maintainers can follow [docs/SIGNING.md](docs/SIGNING.md).

## Architecture

The app stays native and dependency-light:

1. `HingeAngleSensor` reads the Apple HID orientation report.
2. `FoldParameters` converts physical angle into eased visual parameters.
3. `ScreenCaptureEngine` produces IOSurface-backed frames with ScreenCaptureKit while excluding
   LidFold's own overlay.
4. `FoldRenderer` feeds those frames directly into Metal and renders them through a
   click-through, nonactivating overlay on the built-in display.

The distributable uses an Xcode macOS app target for a stable permission identity, resource
compilation, signing, and notarization. Pure logic remains in Swift Package Manager
for fast local and CI validation. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the staged
delivery plan and safety invariants.

## Principles

- Free and open source under MIT, with no accounts, telemetry, or feature paywalls.
- On-device processing only.
- Original product identity and assets.
- A small, auditable native codebase.
- Accessibility first: pause shortcut, reduced-motion mode, and an instant safety escape.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) before making a
large change.

## License

MIT. See [LICENSE](LICENSE).
