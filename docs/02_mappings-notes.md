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

You can also add references here like:

- `videoScenes` profile ↔ `08_midi-mapping-2025-03-15-basement-noise.md`
- `patterns` profile ↔ `08_midi-mapping-2025-04-01-gallery-set.md`
- `pcm30Macros` profile ↔ `08_midi-mapping-2025-03-15-basement-noise.md` (PCM-30 macros on Ch 11; Ch 10 reserved for drum/sequencer stack; video scenes on Ch 12)
- `drumStack` profile ↔ DrumKid default MIDI map (notes + CC 16–31) + DR-550 factory pads (Bank A–D), all on Ch 10 (includes global + per-pad velocity sliders)
- `electribe` profile ↔ Electribe 2S CC map + pattern select (Ch 11) with bank A/B toggles + quick scenes (Bank B uses patterns 1–121)
- `transport` profile ↔ MIDI Start/Continue/Stop controls for external sync setups
