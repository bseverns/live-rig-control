# iOS Deploy

This document covers local build, Xcode run, and signing-related deployment
steps for the iPad app.

## Local Build

From the repo root:

```sh
cd ios
swift build
```

If you need an explicit SDK path:

```sh
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
swift build --sdk "$SDK_PATH" --triple arm64-apple-ios17.0-simulator
```

## Xcode Run Flow

SwiftPM alone is not the whole deployment path for a physical iPad. Use Xcode
for signing and installation.

### First-time setup

1. Open `ios/Package.swift` in Xcode.
2. Select the `LiveRigControlApp` scheme.
3. Choose an iPad device or simulator.
4. Set a unique bundle identifier for the app target and test target.
5. Set your Team in Signing & Capabilities.
6. Build and run once so provisioning and signing are established.

### Xcode checklist

- Confirm the correct app identifier is set.
- Confirm the correct Team is selected.
- Confirm you have replaced the placeholder bundle IDs before shipping a build.
- Confirm `Info.plist` is attached to the target.
- Confirm Local Network capability/usage strings are present.
- Confirm Camera usage string is present for QR scanning.
- Run once on device to validate provisioning.

## GitHub Actions Signed Build

The repo includes a manual signed build workflow:

- `.github/workflows/ios-signed-manual.yml`

Required secrets:

- `IOS_SIGNING_CERT_P12`
- `IOS_SIGNING_CERT_PASSWORD`
- `IOS_PROVISION_PROFILE`

### Preparing secrets

Export your signing assets:

```sh
base64 -i cert.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

Then store those base64 values in the matching GitHub repository secrets.

## Recommended Deployment Pattern

- Use VS Code or your preferred editor for day-to-day changes.
- Use Xcode for signing, device installation, and any simulator/device-specific debugging.
- Use the manual GitHub Actions workflow only when you explicitly want a signed CI artifact path.

## Operational Notes

- The app currently targets iPadOS and uses the `ios/LiveRigControlApp.xcodeproj` target setup.
- `OSC_HOST` in the plist is only a default seed value; runtime state is persisted in app storage.
- For local OSC bridge use, default to loopback or trusted LAN endpoints only.
- Network MIDI accepts hosts in the iPad's MIDI Network Setup contact list by
  default; add a trusted rig host there before using Network MIDI.
