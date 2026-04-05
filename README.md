# live-rig-control

Performer-facing control surface for the hybrid audio-video live rig documented
in the companion `live-rig` repo. This repo is the place where the **touch UI,
MIDI/OSC dispatch, and mapping-driven UX** live.

## What this repo is trying to do

Build a **reliable, mapping-driven control surface** that can run on multiple
devices and send the exact same MIDI + OSC payloads to the rig. The semantic
authority lives in the sibling `live-rig` repo; this repo keeps a runtime
surface map in `src/mappings.json` synced from that authority so web and iPad
stay aligned across:

- **Web app (current):** WebMIDI grid UI for Windows touch devices.
- **iPadOS app (in progress):** SwiftUI mirror of the web UX using Core MIDI.
- **OSC bridge:** optional WebSocket bridge that forwards OSC messages.

The canonical system mapping, device roles, and channel plans live in the
companion `live-rig` repo. This repo is the controller surface that consumes
those mappings and sends real-time signals.

## Current state

- Web UI renders profiles/pads from `src/mappings.json` and sends MIDI via WebMIDI.
- Optional OSC output is sent via a WebSocket bridge (same payload contract as the rig).
- iPadOS app loads the same mapping set from its bundled resource mirror.
- Shared semantic controls are regenerated from the committed mirror `atlas/live-rig.default.json`.

## Start here

- **Atlas interop snapshot:** [`atlas/interop.yaml`](atlas/interop.yaml)
- **Mirrored authority snapshot:** [`atlas/live-rig.default.json`](atlas/live-rig.default.json)
- **Field card (fast ops + failure modes):** [`docs/FIELD_CARD.md`](docs/FIELD_CARD.md)
- **Control reference (what is being controlled, and why):** [`docs/03_control-reference.md`](docs/03_control-reference.md)
- **MSVP operator lane:** [`docs/MSVP_CONTROL_SURFACE.md`](docs/MSVP_CONTROL_SURFACE.md)
- **MSVP smoke test:** [`docs/MSVP_SMOKE_TEST.md`](docs/MSVP_SMOKE_TEST.md)
- **iOS testing notes:** [`docs/ios-testing.md`](docs/ios-testing.md)
- **iOS deploy notes:** [`docs/ios-deploy.md`](docs/ios-deploy.md)

## Quick start

1. Clone this repo:

   ```bash
   git clone https://github.com/bseverns/live-rig-control.git
   cd live-rig-control
   ```

2. Serve the `public/` folder (pick one):

   ```bash
   cd public
   python -m http.server 8080
   ```

3. On the Surface Pro, open Chrome/Edge and visit:

   ```
   http://localhost:8080
   ```

4. When prompted, allow MIDI access. In the UI, select your desired MIDI output
   (loopMIDI bus, hardware interface, etc.).

5. Click pads in the grid. They send MIDI according to `src/mappings.json`. If
   the OSC bridge is running, OSC messages will also be emitted.

## OSC bridge hardening defaults

- The bridge now binds to `127.0.0.1` by default, not all interfaces.
- Allowed browser origins default to `http://localhost:8080` and `http://127.0.0.1:8080`.
- You can require a shared token with `BRIDGE_TOKEN`; the browser can pass it via
  `?osc_token=...` in the page URL or `localStorage.oscBridgeToken`.
- Bridge env examples live in [`server/.env.example`](server/.env.example).

See `docs/01_architecture.md` for an overview of how this ties back into the rig.

## MSVP validation

Validate the controller mapping against the focused MSVP contract mirror and,
when present, the sibling MSVP checkout:

```bash
python3 tools/validate_msvp_live_rig_control.py
```

## Authority sync

Regenerate the shared semantic controls from the committed mirror
`atlas/live-rig.default.json` into both the web and iPad runtime mapping files:

```bash
python3 tools/sync_live_rig_authority.py
python3 tools/sync_live_rig_authority.py --check
```

Refresh that committed mirror from the sibling `live-rig` checkout first when
you want the latest authority export:

```bash
python3 tools/sync_live_rig_authority.py --refresh-from-sibling
```
