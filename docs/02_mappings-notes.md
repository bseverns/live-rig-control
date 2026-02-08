# Mapping Notes

This file is a scratchpad for aligning `src/mappings.json` with the
canonical mapping docs in the `live-rig` repository.

Recommended practice:

- For each show or major revision, create or update a markdown mapping in
  `live-rig` (e.g. `08_midi-mapping-YYYY-MM-DD-SHOWNAME.md`).
- Mirror the relevant parts of that mapping in `src/mappings.json` under
  a dedicated profile (e.g. `videoScenes`, `patterns`, `fxMacros`).
- Use stable `id` values for pads so that changes to labels or notes
  don't break mental or visual associations.
 - For the “why” behind the structure, see `docs/mappings-rationale.md`.

You can also add references here like:

- `videoScenes` profile ↔ `08_midi-mapping-2025-03-15-basement-noise.md`
- `patterns` profile ↔ `08_midi-mapping-2025-04-01-gallery-set.md`
- `pcm30Macros` profile ↔ `08_midi-mapping-2025-03-15-basement-noise.md` (PCM-30 macros on Ch 11; Ch 10 reserved for drum/sequencer stack; video scenes on Ch 12)
- `drumStack` profile ↔ DrumKid default MIDI map (notes + CC 16–31) + DR-550 factory pads (Bank A–D), all on Ch 10 (includes global + per-pad velocity sliders)
- `electribe` profile ↔ Electribe 2S CC map + pattern select (Ch 11) with bank A/B toggles + quick scenes (Bank B uses patterns 1–121)
- `transport` profile ↔ MIDI Start/Continue/Stop controls for external sync setups

## Rationale And Conventions

This section captures why the current mapping is structured the way it is,
so changes stay intentional and interoperable.

## Channel Plan (From `src/mappings.json`)

- `videoScenes`: Ch 12 (kept separate from instrument control so scene changes never collide with performance CCs)
- `pcm30Macros`: Ch 11 (PCM-30 insert controls aimed at the Electribe 2S global channel)
- `electribe`: Ch 11 (shares the PCM-30 channel so inserts and Electribe controls land on the same target)
- `drumStack`: Ch 10 (standard drum channel; includes DrumKid + DR-550 pads and DrumKid CC)
- `patterns`: Ch 1 (pattern selection lane; kept simple and low-traffic)
- `nwWrldInput`: Ch 1 and Ch 2 (two-lane input targeting the NW World slice)
- `transport`: Ch 1 (global MIDI real-time control for external sync)

If a device moves channels, update both the profile and the notes here so
the mapping stays auditable.

## Profile Boundaries

- Profiles are split by performer intent, not by device brand.
- High-traffic performance controls (drums, Electribe parameters) live on
  dedicated profiles to keep quick access and reduce misfires.
- Transport stays isolated to avoid accidental Start/Stop when switching
  between performance profiles.

## Variable Controls (Why Sliders)

- DrumKid and Electribe parameters are continuous values (0–127), so sliders
  map more honestly than binary toggles.
- Sliders default to sending CC values; pads use note/program/realtime for
  discrete actions.
- When a control is binary but still “feels” continuous (e.g. FX On/Off),
  it stays a toggle to avoid ambiguity.

## Velocity Strategy

- `drum_velocity` provides a global velocity for DrumKid note hits.
- Per-pad velocity overrides exist to normalize specific hits without
  touching the global setting.
- This keeps dynamic control available while preserving consistent levels
  for critical sounds.

## Pattern / Bank Selection

- Electribe pattern changes are expressed with Bank Select (MSB/LSB) plus
  Program Change so the UI can expose a single “pattern” slider.
- Bank A/B toggles change the implied bank for subsequent pattern changes.
- The quick scene pads select commonly used patterns for fast recall.

## Interoperability And IDs

- `id` values stay stable even when labels change, so automation, OSC, and
  muscle memory don’t break.
- `ui.role` communicates intent (velocity, pattern, bank) and lets both the
  web UI and iOS UI render controls consistently.
- `target` and `bank` fields are human-readable metadata; keep them aligned
  with the canonical mapping notes in `live-rig`.
