# MSVP Control Surface

This repo now exposes one explicit MSVP page in `src/mappings.json`:

- Profile/page: `msvp`
- Section: `video`
- Purpose: scene cues, macro shaping, and analysis shaping for `MidiVideoSyphonBeats`

For the machine-readable contract mirror, see `contracts/msvp_live_rig_control.yaml`.

For direct OSC routing to MSVP, start the bridge from `server/` with
`OSC_PORT=9010 npm start`; port `9000` remains the bridge default for other rig targets.

## What This Repo Sends To MSVP

### Scene row

Top row of the `msvp` page:

- `vid_scene_intro`
- `vid_scene_crash`
- `vid_scene_soft`
- `vid_scene_clean_camera`
- `vid_state_blackout`

These send:

- OSC primary:
  - `/video/scene/intro`
  - `/video/scene/crash`
  - `/video/scene/soft`
  - `/video/scene/clean_camera`
  - `/rig/state/blackout`

The controller intentionally does not send the MIDI note fallback from this page. That avoids accidental double-trigger semantics.

### Macro row

Middle row of the `msvp` page sends MIDI CC on channel `10`:

- CC1 `linesPerFrame`
- CC2 `maxLineSize`
- CC3 `opacityMin`
- CC4 `effectIntervalBeats`
- CC5 `effectDurationBeats`
- CC6 `bpmSmoothing`
- CC7 `effectBias`

This is the base shaping lane.

### Analysis row

Bottom row of the `msvp` page sends MIDI CC on channel `15` using the same CC map.

This is the bias lane. It adds wind to the same parameter vocabulary instead of replacing the macro lane’s semantic role.

## Stable Semantic ID

A stable semantic ID is the contract key that survives UI and routing changes.

Example:

- `vid_scene_intro` may move on the page or get relabeled for the performer
- but it still means the same MSVP scene

That stability keeps automation, docs, muscle memory, and downstream interop aligned.

## Transport Expectations

- Clock/transport: MIDI only
- Continuous shaping: MIDI CC primary
- Semantic scenes: OSC primary, MIDI note fallback only at the contract/endpoint level

MSVP is follower-only. This repo does not make it a clock owner.

## Failure Modes

### Missing MIDI loopback

If the loopback port is missing:

- MSVP will not receive MIDI clock
- MSVP will not receive macro or analysis CC
- OSC scene cues can still work if the OSC route is alive

### Missing clock

If clock stops:

- MSVP goes stale on the last derived BPM
- MSVP does not become the transport authority
- the fix is upstream clock restoration, not endpoint re-ownership

## Smoke Test Sequence

1. Run `python3 tools/validate_msvp_live_rig_control.py`.
2. Open the `msvp` page.
3. Verify the top row triggers `Intro`, `Crash`, and `Soft` through OSC.
4. Verify `Clean Camera` and `Blackout` reach the shared semantic OSC addresses.
5. Move the macro row and confirm MSVP responds on channel `10`.
6. Move the analysis row and confirm MSVP responds on channel `15`.
7. Verify incoming MIDI clock still comes from the external master or loopback source, not from MSVP itself.

The detailed checklist lives in `docs/MSVP_SMOKE_TEST.md`.
