# MSVP / live-rig-control Contract

This document explains the focused contract between:

- `live-rig-control` as the performer-facing emitter
- `MSVP / MidiVideoSyphonBeats` as the visual endpoint

The machine-readable mirror is [contracts/msvp_live_rig_control.yaml](/Users/bseverns/Documents/GitHub/live-rig-control/contracts/msvp_live_rig_control.yaml). It stays deliberately small: scenes, macro lane, analysis lane, and transport ownership.

## Intent

The contract exists so `src/mappings.json` and `MidiVideoSyphonBeats/data/live_rig_interop.json` can drift independently in Git without drifting semantically on stage.

It fixes four things in place:

1. Stable scene IDs.
2. Stable scene OSC addresses.
3. Stable macro and analysis CC meanings.
4. Stable transport ownership rules.

## Stable Semantic IDs

`vid_scene_intro`, `vid_scene_crash`, `vid_scene_soft`, `vid_scene_clean_camera`, and `vid_state_blackout` are semantic IDs, not cosmetic labels.

That means:

- the UI label can change
- the layout can change
- the fallback MIDI note path can remain implementation-specific

But the semantic meaning of each scene stays fixed.

## Transport Split

### Scene Triggers

- Primary transport: OSC
- Fallback transport: MIDI note
- Controller behavior: `live-rig-control` emits OSC scene commands on the `msvp` profile
- Endpoint fallback: MSVP still exposes note fallback on channel `10`, notes `60..62`

The controller intentionally keeps scenes OSC-only here to avoid double-trigger semantics. The fallback note vocabulary still exists in the contract and in MSVP for manual/debug paths.

### Macro Lane

- Primary transport: MIDI CC
- Channel: `10`
- OSC equivalent: `/msvp/macro/<param>`

CC `1..7` map to:

| CC | Param |
| --- | --- |
| 1 | `linesPerFrame` |
| 2 | `maxLineSize` |
| 3 | `opacityMin` |
| 4 | `effectIntervalBeats` |
| 5 | `effectDurationBeats` |
| 6 | `bpmSmoothing` |
| 7 | `effectBias` |

### Analysis Lane

- Primary transport: MIDI CC
- Channel: `15`
- OSC equivalent: `/msvp/analysis/<param>`

It uses the same parameter vocabulary as the macro lane, but with a different semantic role: analysis adds bias, macro sets base intent.

## Transport Ownership

MSVP is follower-only.

- Clock/transport: MIDI
- Continuous shaping: MIDI CC
- Semantic scenes: OSC primary, MIDI note fallback

MSVP never becomes the clock source. If clock is missing, it becomes stale; it does not become authoritative.

## Failure Semantics

- Missing MIDI loopback: MSVP loses clock and CC control. OSC scenes may still work if the OSC path is up.
- Stale clock: MSVP freezes at the last derived BPM until ticks return.
- Contract mismatch: validator fails; do not trust the pairing until the drift is resolved.
- Unknown semantic ID: treat as unmapped drift, not as a prompt to guess.

## TODOs From Current Evidence

- TODO: `live-rig-control` does not yet auto-fail over from OSC scene commands to the MIDI note fallback path.
- TODO: the checked-in MSVP interop file keeps `runtime.rigTunedMode` off by default; deployment enablement stays operator-controlled.

## Validation Commands

```bash
python3 tools/validate_msvp_live_rig_control.py
python3 tools/validate_msvp_live_rig_control.py --live-rig-mappings src/mappings.json
python3 tools/validate_msvp_live_rig_control.py --live-rig-mappings ios/Sources/LiveRigControlApp/Resources/mappings.json
python3 tools/validate_msvp_live_rig_control.py --msvp-interop ../MSVP/MidiVideoSyphonBeats/data/live_rig_interop.json
python3 tools/validate_msvp_live_rig_control.py --live-rig-mappings src/mappings.json --msvp-interop ../MSVP/MidiVideoSyphonBeats/data/live_rig_interop.json
```
