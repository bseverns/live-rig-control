# live-rig-control

Browser-based control surface for the hybrid audio–video live rig documented in
the companion `live-rig` repo.

This repo provides a WebMIDI-capable grid UI (optimized for a Surface Pro 7
running Windows 11) that can:

- trigger **video/scene/pattern changes** via MIDI and/or OSC
- present **profiles/pages** that mirror the mapping docs in `live-rig`
- talk directly to your DAW / bridge via WebMIDI, and optionally via an OSC
  bridge server

The canonical system mapping, device roles, and channel plans live in
the companion `live-rig` repo.
This repo is the performer-facing control surface that reads from a
structured `mappings.json` file.

## Quick start

1. Clone this repo:

   ```bash
   git clone <your-repo-url>
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

See `docs/01_architecture.md` for an overview of how this ties back into the rig.
