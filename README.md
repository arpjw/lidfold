# LidFold

LidFold is a free, open-source macOS experiment that makes the desktop visually fold as a
MacBook lid closes. The project is a clean-room implementation inspired by the interaction,
not the branding, code, copy, or assets of any commercial app.

The first working slice is a native menu-bar app that reads the hinge angle on compatible
Apple silicon MacBooks. The next slice will capture the display with ScreenCaptureKit and
render the fold through a click-through Metal overlay.

## Status

- [x] Native menu-bar app
- [x] Live hinge-angle reader
- [x] Tested angle-to-effect mapping
- [x] Screen Recording permission boundary
- [ ] Screen Recording onboarding UI
- [ ] ScreenCaptureKit display capture
- [ ] Metal perspective, blur, shade, and shadow renderer
- [ ] Multi-display and display-reconfiguration handling
- [ ] Settings window and launch at login
- [ ] Signed, notarized universal DMG

## Requirements

- macOS 14 or newer
- An Apple silicon MacBook with the lid-orientation HID sensor
- Swift 6.3 or newer for command-line builds
- Full Xcode for app bundling, signing, Metal shader compilation, and notarization

The lid sensor is not a public Apple API. LidFold reads an undocumented HID feature report,
so hardware and future macOS compatibility are not guaranteed. The eventual desktop effect
will require Screen Recording permission, but frames will remain on-device.

## Build the sensor prototype

```sh
swift build
swift run LidFold --diagnose
swift run LidFold
```

`swift run LidFold` launches a menu-bar-only process. Quit it from the menu-bar menu.
Run `swift test` after selecting a full Xcode installation; Apple's standalone Command Line
Tools SDK does not include the XCTest module.

## Continuous integration and releases

GitHub Actions builds and tests every pull request on macOS with Xcode 26.3. Version tags
matching `v*` create a checksummed source archive and a GitHub release. Native `.app` and DMG
artifacts will be added after the app-bundle, signing, and notarization pipeline is in place;
until then, releases remain reproducible from source and do not imply an Apple signature.

## Architecture

The app stays native and dependency-light:

1. `HingeAngleSensor` reads the Apple HID orientation report.
2. `FoldParameters` converts physical angle into eased visual parameters.
3. A forthcoming `ScreenCaptureEngine` will produce IOSurface-backed frames with
   ScreenCaptureKit while excluding LidFold's own overlay.
4. A forthcoming `FoldRenderer` will feed those frames directly into Metal and render one
   click-through, nonactivating overlay per display.

The distributable will use an Xcode macOS app target for a stable permission identity, Metal
resource compilation, signing, and notarization. Pure logic remains in Swift Package Manager
for fast local and CI validation. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the staged
delivery plan and safety invariants.

## Principles

- Free forever for individual use, with no accounts, telemetry, or feature paywalls.
- On-device processing only.
- Original product identity and assets.
- A small, auditable native codebase.
- Accessibility first: pause shortcut, reduced-motion mode, and an instant safety escape.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) before making a
large change.

## License

MIT. See [LICENSE](LICENSE).
