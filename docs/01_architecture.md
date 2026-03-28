# Architecture Overview

`live-rig-control` is a browser-based control surface intended to run on a
Surface Pro and talk to the hybrid live rig defined in the `live-rig` repo.

## Components

- **Surface Pro + Browser**
  - Loads `public/index.html`.
  - Uses WebMIDI to send MIDI to loopMIDI / hardware.
  - Optionally connects via WebSocket to the OSC bridge.

- **Mappings Layer**
  - `src/mappings.json` defines runtime profiles (pages) and pads.
  - Each pad has semantic IDs and can emit MIDI and/or OSC.
  - Adjacent artifacts such as `src/maschine_mk1_profile.json` can document
    hardware mirror decks without making them active web/iPad pages.

- **OSC Bridge (optional)**
  - `server/osc-bridge.js` runs on the same machine as the browser or on a
    nearby host.
  - Receives validated JSON over WebSocket and forwards OSC over UDP.
  - Binds to `127.0.0.1` by default and can optionally require a shared token.

- **Live Rig**
  - DAW, video engine, and hardware synths receive MIDI/OSC and act
    according to the mapping documented in `live-rig`.

The goal is to keep device/channel/scene knowledge encoded in `live-rig`
while `live-rig-control` focuses on the performer-facing interface.

That same rule applies when a subset of the system is mirrored onto dedicated
hardware. The Maschine MK1 profile is documented here as a narrow scene/event
deck, but `live-rig-control` remains the canonical mapping layer and the
Maschine deck does not become a transport owner.

For mapping structure rationale, see `docs/mappings-rationale.md`.
For a verbose walkthrough of the control domains and why they are split the way
they are, see `docs/03_control-reference.md`.
