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
