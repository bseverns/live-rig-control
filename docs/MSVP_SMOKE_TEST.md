# MSVP Smoke Test

Use this after changing either `src/mappings.json` or `MidiVideoSyphonBeats/data/live_rig_interop.json`.

## Preflight

1. Run:

   ```bash
   python3 tools/validate_msvp_live_rig_control.py
   ```

2. Confirm the OSC bridge is up if you plan to test scene cues from the controller.
3. Confirm MSVP is pointed at a real MIDI loopback/input, not only Java’s `Real Time Sequencer`.

## Checklist

### 1. Loopback port exists

- Expected: a real loopback/input port such as `IAC Bus 1` or equivalent exists.
- Failure smell: MSVP only shows `Real Time Sequencer`, or no useful MIDI input at all.

### 2. Shared semantic scene/state controls trigger correctly

- Open the `msvp` page in `live-rig-control`.
- Trigger:
  - `Scene Intro`
  - `Scene Crash`
  - `Scene Soft`
  - `Clean Camera`
  - `Blackout`
- Expected:
  - MSVP receives `/video/scene/intro`
  - MSVP receives `/video/scene/crash`
  - MSVP receives `/video/scene/soft`
  - the shared semantic lane receives `/video/scene/clean_camera`
  - the shared semantic lane receives `/rig/state/blackout`
  - the visible preset/behavior changes accordingly

### 3. Macro controls move expected parameters

- Move each macro slider on the middle row.
- Expected:
  - channel `10`
  - CC `1..7`
  - parameter meanings stay:
    - `linesPerFrame`
    - `maxLineSize`
    - `opacityMin`
    - `effectIntervalBeats`
    - `effectDurationBeats`
    - `bpmSmoothing`
    - `effectBias`

### 4. Analysis controls add bias on their own lane

- Put a macro slider somewhere nonzero first.
- Then move the corresponding analysis slider on the bottom row.
- Expected:
  - channel `15`
  - CC `1..7`
  - analysis adds bias without replacing the macro lane’s role

### 5. Clock / transport remain one-way toward MSVP

- Start the real upstream clock source.
- Expected:
  - MSVP follows incoming MIDI clock
  - MSVP does not generate clock
  - if clock stops, MSVP becomes stale rather than authoritative

## Notes

- Scene commands are OSC-primary from this controller page.
- MIDI note fallback remains part of the shared contract and MSVP endpoint, but `live-rig-control` does not auto-fail over to it yet.
