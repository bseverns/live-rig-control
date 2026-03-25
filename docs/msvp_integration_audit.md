# MSVP Integration Audit

This audit records what the repo exposed before the MSVP alignment pass and what that meant for the shared interop.

## Sources Reviewed

- `README.md`
- `atlas/interop.yaml`
- `docs/03_control-reference.md`
- `src/mappings.json`
- `../MSVP/MidiVideoSyphonBeats/data/live_rig_interop.json`

## Findings

### 1. Stable scene IDs already existed

The repo already exposed:

- `vid_scene_intro`
- `vid_scene_crash`
- `vid_scene_soft`

Those IDs already matched the MSVP scene vocabulary and already pointed at the canonical OSC addresses:

- `/video/scene/intro`
- `/video/scene/crash`
- `/video/scene/soft`

That meant the semantic scene layer was mostly there already.

### 2. The old scene page was not explicitly an MSVP page

Before alignment, the repo had a small `videoScenes` profile with only three pads. It did not make the broader MSVP surface explicit, because macro and analysis lanes were not present in `src/mappings.json`.

Result: scenes looked canonical, but the actual MSVP control lane was incomplete.

### 3. Scene intent was duplicated across MIDI and OSC

The old `videoScenes` pads emitted both:

- MIDI note fallback on channel `12`
- matching OSC scene commands

That was acceptable for a generic video-target page, but it was ambiguous for MSVP’s rig-tuned expectations, where scenes are OSC-primary and note fallback is a separate concern.

Result: the controller could double-fire the same semantic scene change through two transports at once.

### 4. Scene overlap already existed elsewhere in the repo

`nwWrldFeed` also exposed scene-like verbs (`intro`, `crash`, `soft`) under a different namespace.

This was not an ID collision, but it was a performer-facing overlap:

- MSVP scenes
- NW World scenes

Result: the repo needed one explicit MSVP page so scene semantics stayed easy to reason about.

### 5. Transport ownership was already correctly separate

The repo already kept transport isolated:

- `transport` profile for MIDI realtime commands
- no evidence that MSVP was expected to generate or own clock
- `atlas/interop.yaml` already described this repo as an emitter, not a state mirror

Result: the transport ownership rule did not need a behavioral rewrite, only clearer documentation.

## Alignment Applied

The alignment pass turned those findings into explicit repo behavior:

- Replaced `videoScenes` with an explicit `msvp` profile.
- Kept the stable scene IDs and canonical OSC addresses.
- Made scene cues OSC-only in `live-rig-control` to avoid accidental double-trigger semantics.
- Added first-party MSVP macro controls on MIDI channel `10`.
- Added first-party MSVP analysis controls on MIDI channel `15`.
- Added a focused validator and contract mirror to catch drift.

## Residual Risk

- The controller still does not auto-switch from OSC scenes to MIDI note fallback.
- The checked-in MSVP interop file still ships with `runtime.rigTunedMode` off by default, so operator setup still matters.
