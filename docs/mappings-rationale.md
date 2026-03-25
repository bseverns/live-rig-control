# Mapping Rationale

This document explains why the current `src/mappings.json` structure looks
the way it does. It is meant to be read alongside the canonical mapping
notes in the `live-rig` repository.

## Guiding Principles

- Keep performer intent obvious on the surface.
- Separate high‑risk controls (transport, scene changes) from dense
  performance pages.
- Prefer continuous controls for continuous parameters (sliders for CC).
- Use stable `id` values so automation, OSC, and muscle memory survive edits.
- Make the channel plan explicit and easy to audit.

## Channel Plan

- Ch 10: Drum and sequencer stack (DrumKid + DR‑550 + SQ‑64 rhythm lane).
- Ch 11: PCM‑30 insert controls and Electribe 2S controls.
- MSVP scenes: OSC-first semantic triggers.
- Ch 10: MSVP macro shaping lane.
- Ch 15: MSVP analysis shaping lane.
- Ch 1–2: NW World input lanes.

Rationale:

- Ch 10 stays dedicated to drums because it is the de facto standard and
  keeps rhythm signals predictable.
- Ch 11 keeps insert controls and Electribe parameters aligned on the same
  target device channel, so insert changes always hit the expected rig node.
- MSVP scene triggers stay OSC-first so the semantic cue is explicit and does
  not double-fire alongside a fallback note path.
- Ch 10 carries MSVP macro shaping because it is a compact performance lane.
- Ch 15 keeps MSVP analysis bias separate from macro base intent.
- Ch 1–2 are reserved for NW World input, which often travels a different
  processing path.

## Profile Boundaries

- `drumStack` is a full performance page with DrumKid hits + DrumKid CC
  sliders + DR‑550 pad banks. It trades density for speed.
- `electribe` is focused on CC parameters and pattern selection. It keeps
  sound shaping on one page, with pattern selection as fast access.
- `pcm30Macros` keeps minimal insert controls separate from the Electribe
  CC page so “macro” moves do not crowd parameter sliders.
- `msvp` is isolated so scene cues, macro shaping, and analysis shaping stay on
  one explicit page instead of being spread across generic video controls.
- `transport` is isolated so Start/Stop never fires during parameter edits.
- `patterns` and `nwWrldInput` remain compact utility pages.

## Variable Controls And Sliders

- DrumKid and Electribe parameters are continuous (0–127), so sliders are
  the most honest interface.
- Binary controls stay as toggles to preserve “on/off” clarity.
- Sliders are labeled with parameter names and keep their CC numbers in the
  mapping metadata for auditability.

## Velocity Strategy

- A global `drum_velocity` slider sets the default velocity for DrumKid hits.
- Per‑pad overrides exist to normalize specific hits without changing the
  overall feel.
- This keeps dynamics available while allowing predictable levels for
  key sounds.

## Pattern And Bank Selection (Electribe 2S)

- Pattern changes use Bank Select (MSB/LSB) + Program Change behind the UI.
- Bank A/B toggles let the performer switch banks without scrolling.
- Quick scene pads map to commonly used patterns for fast recall.

## Device Notes

- DrumKid:
  - Notes are on Ch 10 (standard drum channel).
  - CC 16–31 map to DrumKid parameters; exposed as sliders for continuous
    control.
- DR‑550:
  - Factory pad banks A–D are surfaced so all pad sounds can be triggered.
  - Banks live on Ch 10 alongside DrumKid for one‑page drum performance.
- Electribe 2S:
  - CC parameters are exposed as sliders, including filter, envelope, FX,
    and modulation depth/speed.
  - Pattern selection is simplified to a single slider plus bank toggles.
- PCM‑30:
  - Minimal “insert” controls are on Ch 11, matching the Electribe channel.
  - This allows one controller (PCM‑30) to drive inserts on the Electribe
    without re‑channeling mid‑performance.

## Interoperability And Maintenance

- Use `ui.role` for intent (`velocity`, `pattern`, `patternBank`) so the web
  and iOS UIs render the same controls.
- Keep `target` and `bank` metadata aligned with the `live-rig` notes.
- When a device channel changes, update the profile and this document.
