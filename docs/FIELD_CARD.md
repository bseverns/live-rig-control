# FIELD CARD — Live Rig Control

## Purpose
A browser-based grid control surface that fires MIDI/OSC cues for the live rig.
Built to mirror the rig mapping docs while staying fast, legible, and stage-proof.

## Quickstart
1. Serve `public/` (ex: `python -m http.server 8080`).
2. Open `http://localhost:8080` and grant MIDI access.
3. Pick a MIDI output, toggle OSC if you have the bridge on.

## Primary endpoints/ports

| Interface | Default | Protocol | What it does |
| --- | --- | --- | --- |
| Static UI | `http://localhost:8080` | HTTP | Serves the control surface UI. |
| OSC bridge | `ws://127.0.0.1:9001` | WebSocket | Ships OSC payloads when enabled; localhost-only by default. |
| MIDI out | Device-specific | WebMIDI | Sends notes/CCs per `src/mappings.json`. |

## Hardware mirrors
- `src/mappings.json` remains the only runtime-loaded surface map.
- `src/maschine_mk1_profile.json` documents a first-pass Maschine MK1 scene/event deck for later hardware integration.
- The Maschine deck is complementary hardware, not a transport owner and not a replacement for the main web/iPad surface.

## Common failures + fixes
1. **No MIDI outputs listed** → Use Chrome/Edge with WebMIDI enabled and reconnect devices.
2. **OSC toggle does nothing** → Start the OSC bridge at port `9001`, confirm the WS URL, and if auth is enabled provide `?osc_token=...`.
3. **Pads do nothing / wrong target** → Confirm `src/mappings.json` matches your rig mappings.
4. **Maschine MK1 deck does not appear in the browser** → Expected on this pass. The hardware profile is documented in `src/maschine_mk1_profile.json` and is not yet rendered by the runtime UI.

## When not to use this system
- When you need bidirectional feedback or state sync (this UI is mostly fire-and-forget).
- When you’re offline from the rig’s mapping canon and can’t trust the IDs.
