# Maschine MK1 Profile

`src/maschine_mk1_profile.json` is the first-pass machine-readable profile for
a Native Instruments Maschine MK1 used as a dedicated 4x4 hardware scene/event
deck for the hybrid live rig.

This is intentionally a documentation and mapping-groundwork artifact. It does
not add a new runtime page to the web/iPad surface, and it does not change
transport ownership inside the rig.

## Purpose

The Maschine MK1 fits here as a narrow, high-legibility hardware node for:

- safe/show-state actions
- named scene triggers
- hybrid audiovisual one-shot events
- section and utility cues

Its job is to make a small set of high-impact gestures physically reliable
without turning the controller into a master brain.

## Why Maschine Fits The Rig

- Sixteen physical pads map cleanly to a 4x4 deck with row-level meaning.
- The pad format is good for discrete intent: scene recall, event strikes, and
  emergency show-state actions.
- It can mirror a subset of `live-rig-control` semantics without taking over
  the rest of the control surface.
- The deck stays readable under show pressure because each row has one job.

## Why It Does Not Replace Edirol, frZone, Or live-rig-control

- Edirol remains the continuous shaping surface. Maschine is not for dense CC
  riding or parameter sculpting.
- frZone remains the analysis lane. Maschine is not where analysis bias or deep
  response tuning should live.
- `live-rig-control` remains the canonical mapping-driven system. Maschine is a
  hardware mirror of selected semantics, not a new source of truth.
- The deck is not a transport owner and should not inherit global start/stop or
  master clock responsibility.

## Pad Map

| Pad | Label | Stable ID | Transport | Target lane | Rationale | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `BLACKOUT` | `masch.safe.blackout` | OSC-first | Safe / show-state | Immediate rescue action with the clearest possible placement. | Critical |
| 2 | `SAFE CLEAN` | `masch.safe.clean` | OSC-first | Safe / show-state | Return to a trusted clean state without touching global transport. | High |
| 3 | `SOFT RESET` | `masch.safe.soft_reset` | OSC-first | Safe / show-state | Recover from buildup or drift without turning the deck into a transport page. | High |
| 4 | `FREEZE_HOLD` | `masch.safe.freeze` | OSC-first | Safe / show-state | Hold the current state long enough to recover or inspect. | High |
| 5 | `INTRO` | `masch.scene.intro` | OSC-first | Named scene | Entry-world recall should stay semantic and explicit. | High |
| 6 | `CRASH` | `masch.scene.crash` | OSC-first | Named scene | Large world change belongs on a scene row, not in a dense parameter page. | High |
| 7 | `DRIFT` | `masch.scene.drift` | OSC-first | Named scene | Keeps slower world-state drift separate from event strikes. | High |
| 8 | `HARSH` | `masch.scene.harsh` | OSC-first | Named scene | High-impact scene change with clear semantic ownership. | High |
| 9 | `NOISE_BURST` | `masch.event.noise_burst` | Hybrid MIDI+OSC | Hybrid event | One strike can fan out to both audio and visual accent layers. | Medium |
| 10 | `VOICE_SHARD` | `masch.event.voice_shard` | Hybrid MIDI+OSC | Hybrid event | Discrete audiovisual shard event, kept off the scene row. | Medium |
| 11 | `LOW_HIT` | `masch.event.low_hit` | Hybrid MIDI+OSC | Hybrid event | Fast low-register impact cue with coupled audiovisual semantics. | Medium |
| 12 | `HIGH_HIT` | `masch.event.high_hit` | Hybrid MIDI+OSC | Hybrid event | Fast high-register impact cue with coupled audiovisual semantics. | Medium |
| 13 | `SECTION_A` | `masch.section.a` | OSC-first | Section / utility | Structural steering cue, not a transport command. | Medium |
| 14 | `SECTION_B` | `masch.section.b` | OSC-first | Section / utility | Secondary form cue for deliberate section changes. | Medium |
| 15 | `TEXTURE_TOGGLE` | `masch.texture.toggle` | Hybrid MIDI+OSC | Section / utility | Discrete texture enable/disable that may need both audio and visual fan-out. | Medium |
| 16 | `MANUAL_OVERRIDE` | `masch.override.manual` | OSC-first | Section / utility | Changes operator posture and therefore stays semantic and isolated. | High |

## Operator Heuristics

- Top row rescues the show.
- Second row changes the world.
- Third row strikes the world.
- Fourth row steers the form.

These heuristics matter more than cosmetic labels. If labels change later, the
stable IDs and the row meaning should remain intact.

## Transport Model

- OSC-first semantic actions:
  `BLACKOUT`, `SAFE CLEAN`, `SOFT RESET`, `FREEZE_HOLD`, `INTRO`, `CRASH`,
  `DRIFT`, `HARSH`, `SECTION_A`, `SECTION_B`, `MANUAL_OVERRIDE`
- Hybrid MIDI+OSC actions:
  `NOISE_BURST`, `VOICE_SHARD`, `LOW_HIT`, `HIGH_HIT`, `TEXTURE_TOGGLE`

Where the exact downstream OSC addresses or MIDI note numbers are not yet fixed
in this repo, the JSON artifact keeps those fields as explicit placeholders.
That is intentional. This pass preserves stable identity and transport class
without pretending the downstream routing is already finalized.

## Future Integration Possibilities

- Add a narrow translator/bridge that converts Maschine MK1 pad input into the
  existing semantic IDs and transport rules.
- Mirror selected deck state back to pad LEDs once the routing path is stable.
- Promote individual pads into `src/mappings.json` only if the runtime UI needs
  to render or test them directly.
- Confirm the final OSC addresses and MIDI note/channel values against the
  canonical `live-rig` mapping before any show use.

## Failure Containment And Fallback Use

- If Maschine is disconnected, the web/iPad surface still owns the canonical
  mappings and can perform the same semantic work.
- If OSC routing is down, do not silently reinterpret OSC-first pads as random
  MIDI gestures. Treat that as degraded capability and fall back to the primary
  surface.
- If the hybrid event path is incomplete, use the deck only for the actions
  whose downstream mappings are confirmed.
- If the rig drifts from the documented stable IDs, fix the mapping before the
  next show rather than improvising new semantics on stage.
