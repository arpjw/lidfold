# LidFold architecture

## Build strategy

LidFold uses a hybrid native build:

- A Swift package holds the dependency-free core, hardware diagnostics, and unit tests.
- A real Xcode macOS application target will own the distributable app, bundle identity,
  entitlements, Metal resources, signing, and notarization.
- `scripts/build-app.sh` creates an ad-hoc development bundle until the Xcode target lands.
- GitHub Actions is the canonical clean environment for builds and tests.

The stable app bundle matters because macOS Screen Recording authorization is associated with
the signed application identity. Xcode is also the standard build path for compiling `.metal`
sources into the app's default Metal library. We will not commit generated dependency folders
or make a third-party project generator mandatory.

## Runtime ownership

`AppController` will be the sole main-actor owner of application state. It coordinates these
components:

1. `HingeMonitor` reads the HID sensor away from the main actor and publishes sanitized angles.
2. `FoldActivationController` smooths readings and applies activation hysteresis. Missing or
   invalid readings always disable the effect.
3. `DisplayTopology` maps ScreenCaptureKit displays to AppKit screens. The first release affects
   only the built-in display.
4. `ScreenCaptureEngine` owns the ScreenCaptureKit stream and emits complete video frames.
5. `OverlayController` owns one nonactivating, click-through panel per affected display.
6. `FoldRenderer` binds captured IOSurface-backed pixel buffers to Metal textures and draws on
   frame arrival.

## Delivery sequence

### Slice 1: pass-through overlay

- Explain and request Screen Recording permission from a user-initiated action.
- Capture the built-in display while excluding LidFold itself.
- Render an unchanged frame into a full-screen click-through overlay.
- Provide a manual Show/Hide menu command.

Acceptance criteria: no feedback loop, no duplicate captured cursor, input passes through, full
screen Spaces remain usable, and every capture/topology/sleep failure immediately hides the
overlay.

### Slice 2: physical fold

- Move HID polling to a serial queue or actor.
- Add smoothing and activation hysteresis.
- Render perspective compression through a Metal textured quad.
- Draw only when a new frame or fold parameter arrives.

### Slice 3: visual styles and resilience

- Add GPU blur, shading, and edge shadow.
- Add reduced-motion and performance controls.
- Rebuild capture after display changes, sleep, wake, or session changes.
- Measure frame time, WindowServer load, and idle power use across supported MacBooks.

### Slice 4: distribution

- Add Developer ID signing and Apple notarization using repository secrets.
- Produce a universal `.app`, DMG, checksums, and release notes.
- Keep unsigned source builds available without an Apple account.

## Safety invariants

The overlay must fail open. Any invalid frame, stream error, pause, sleep, session lock, or
display-topology change hides the overlay before recovery begins. The opaque panel is never
shown until capture has started and at least one complete frame is available.

Captured pixels stay on-device. LidFold has no account, analytics, network service, or content
upload path.

## Compatibility boundary

ScreenCaptureKit, Metal, AppKit, and Core Graphics are supported Apple frameworks. The hinge
sensor report is undocumented. All HID-specific behavior remains isolated so model-specific or
future macOS changes can be tested and replaced without touching capture or rendering code.
