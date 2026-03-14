# iOS App History

This file replaces the old `ios-app-todo.md`.

The original TODO document stopped being an active planning artifact once the
SwiftUI app shipped its core control-surface behavior. The useful operational
content has been split into:

- [`docs/ios-testing.md`](ios-testing.md)
- [`docs/ios-deploy.md`](ios-deploy.md)

## Historical Summary

The iOS work was originally scoped to:

- mirror the web UI on iPad,
- replace WebMIDI with Core MIDI,
- preserve the same mapping-driven MIDI and OSC behavior.

### Major milestones completed

- SwiftUI app created under `ios/`
- bundled mappings loaded at launch
- profile bar and grid UI implemented
- toggle, momentary, and slider controls implemented
- Core MIDI send implemented for note, CC, program, and realtime messages
- OSC client implemented with host persistence and reconnect behavior
- QR-based host capture added
- iPad-only Xcode target created
- fixture mappings and mapping-validation tests added

## Why the old TODO file was retired

It had drifted into a mix of:

- completed checklist items,
- old implementation sketches,
- testing notes,
- deployment notes,
- historical context.

That made it misleading as a "TODO" and harder to use as an operator reference.

## Current Source Of Truth

- Runtime behavior: `ios/Sources/LiveRigControlApp/`
- Shared mappings: `src/mappings.json`
- Bundled iOS mappings: `ios/Sources/LiveRigControlApp/Resources/mappings.json`
- iOS testing notes: [`docs/ios-testing.md`](ios-testing.md)
- iOS deploy notes: [`docs/ios-deploy.md`](ios-deploy.md)
