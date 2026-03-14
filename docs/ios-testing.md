# iOS Testing

This document captures the live testing and validation workflow for the iPad app.

## Automated Checks

### Mapping validation

From the `ios/` directory:

```sh
swift run MappingValidator --mappings ../src/mappings.json
```

### Swift tests

If the local toolchain is aligned:

```sh
swift test --enable-swift-testing --filter MappingValidatorTests
```

If you are building against a specific SDK, prefer the pattern below so
`SDKROOT` does not interfere with manifest compilation:

```sh
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
swift build --sdk "$SDK_PATH"
```

## Manual Smoke Tests

### Core app behavior

- App launches without crashing.
- Profiles render in the top bar.
- Pad grid renders for the selected profile.
- Toggle pads change state correctly.
- Momentary pads stay active only while pressed.
- Slider values update and send only the intended control values.

### MIDI behavior

- No MIDI device connected: UI remains usable and no send errors surface.
- MIDI outputs enumerate correctly after app launch.
- Changing the selected MIDI output updates the target send port.
- MIDI sends no-op cleanly when no output is selected.
- Note, CC, Program Change, and realtime messages land on the expected target.

### OSC behavior

- OSC can be enabled and disabled from the app UI.
- Host or endpoint updates persist after relaunch.
- Disconnect/reconnect behavior is visible in the status UI.
- Queued OSC messages drain correctly after reconnect.
- UDP endpoint form works, for example `udp://192.168.1.10:9000`.
- WebSocket endpoint form still works for the legacy bridge path.

### MN42 bridge behavior

- Select the `MOARkNOBS-42 Slots (OSC Bridge)` profile.
- Set `OSC Host` to `udp://<bridge-host>:9000`.
- Enable `OSC Bridge`.
- Move several sliders and confirm the MN42 bridge receives `/mn42/cmd`
  payloads for the expected slot numbers and values.

## Device Checklist

On a real iPad build:

- Local Network permission prompt appears when expected.
- Camera permission prompt appears only when QR scanning is used.
- QR scan updates the OSC host or endpoint correctly.
- App relaunch restores selected profile, MIDI output, and OSC enabled state.
- App behaves correctly in both portrait and landscape if those orientations are enabled.

## Notes

- The app bundles its mappings from `ios/Sources/LiveRigControlApp/Resources/mappings.json`.
- The canonical editable mapping source remains `src/mappings.json`.
- If testing fails because of local Swift/Xcode mismatch, record the exact
  `swift --version`, `xcodebuild -version`, and SDK used rather than treating
  it as an app regression.
