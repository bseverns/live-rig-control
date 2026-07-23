# Live Rig Control Operator Handbook

Generated from `src/mappings.json`. Edit the mapping, then run `npm --prefix server run generate-handbook`.

| Profile | Section | Layout | Controls |
| --- | --- | --- | --- |
| Transport | show | performanceDeck | 3 |
| Patterns | show | performanceDeck | 1 |
| Seeds | sound | parameterBoard, min card 180px | 12 |
| Drum Pads | sound | mappedGrid | 47 |
| Drum Controls | sound | parameterBoard, min card 180px | 16 |
| Synth | sound | parameterBoard, min card 180px | 25 |
| MSVP | video | parameterBoard, min card 180px | 21 |
| Video Feed | video | mappedGrid | 12 |
| FX Macros | video | parameterBoard, min card 180px | 18 |
| Video Input | video | mappedGrid | 26 |
| Controller Slots | setup | parameterBoard, min card 120px | 42 |

## Transport

- ID: `transport`
- Section: `show`
- Layout: `performanceDeck`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `transport_start` | Start | critical | never | MIDI realtime start | MIDI realtime Start (FA). |
| `transport_continue` | Continue | critical | never | MIDI realtime continue | MIDI realtime Continue (FB). |
| `transport_stop` | Stop | critical | never | MIDI realtime stop | MIDI realtime Stop (FC). |

## Patterns

- ID: `patterns`
- Section: `show`
- Layout: `performanceDeck`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `pattern_a` | Pattern A | medium | never | MIDI note 40 ch 1 |  |

## Seeds

- ID: `seedbox`
- Section: `sound`
- Layout: `parameterBoard, min card 180px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `seedbox_mode_local` | Local Clock | low | never | MIDI CC 15 ch 1 | SeedBox mode preset: internal clock, no transport latch. |
| `seedbox_mode_follow` | Follow Clock | low | never | MIDI CC 15 ch 1 | SeedBox mode preset: follow external clock. |
| `seedbox_mode_follow_latch` | Follow+Latch | low | never | MIDI CC 15 ch 1 | SeedBox mode preset: follow external clock and latch transport. |
| `seedbox_focus_seed` | Focus Seed | low | never | MIDI CC 21 ch 1 | MN42 param map CC21: divide 0-127 across the active SeedBox seed count. |
| `seedbox_seed_pitch` | Pitch | low | never | MIDI CC 22 ch 1 | MN42 param map CC22: maps 0-127 to roughly -24 to +24 semitones. |
| `seedbox_seed_density` | Density | low | never | MIDI CC 23 ch 1 | MN42 param map CC23: seed density macro. |
| `seedbox_seed_probability` | Probability | low | never | MIDI CC 24 ch 1 | MN42 param map CC24: seed probability macro. |
| `seedbox_seed_jitter` | Jitter | low | never | MIDI CC 25 ch 1 | MN42 param map CC25: seed timing jitter macro. |
| `seedbox_seed_tone` | Tone | low | never | MIDI CC 26 ch 1 | MN42 param map CC26: seed tone macro. |
| `seedbox_seed_spread` | Spread | low | never | MIDI CC 27 ch 1 | MN42 param map CC27: seed stereo spread macro. |
| `seedbox_seed_mutate` | Mutate | low | never | MIDI CC 28 ch 1 | MN42 param map CC28: seed mutation depth macro. |
| `seedbox_quantize` | Quantize | low | never | MIDI CC 18 ch 1 | SeedBox quantize control CC18. Value encoding follows the SeedBox MN42 map. |

## Drum Pads

- ID: `drumStackNotes`
- Section: `sound`
- Layout: `mappedGrid`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `drumkid_kick` | Kick (C1/36) | medium | never | MIDI note 36 ch 10 | DrumKid default note output: Kick C1 (36) on Ch 10. |
| `drumkid_click` | Click (C#1/37) | medium | never | MIDI note 37 ch 10 | DrumKid default note output: Click C#1 (37) on Ch 10. |
| `drumkid_snare` | Snare (D1/38) | medium | never | MIDI note 38 ch 10 | DrumKid default note output: Snare D1 (38) on Ch 10. |
| `drumkid_hat_closed` | HH Closed (F#1/42) | medium | never | MIDI note 42 ch 10 | DrumKid default note output: Closed hat F#1 (42) on Ch 10. |
| `drumkid_tom` | Tom (G1/43) | medium | never | MIDI note 43 ch 10 | DrumKid default note output: Tom G1 (43) on Ch 10. |
| `drum_velocity` | Velocity | low | never | UI velocity | Global velocity for note pads in this profile. |
| `drumkid_kick_vel` | Kick Vel | low | never | UI velocityOverride | Per-pad velocity override for DrumKid note pad. |
| `drumkid_click_vel` | Click Vel | low | never | UI velocityOverride | Per-pad velocity override for DrumKid note pad. |
| `drumkid_snare_vel` | Snare Vel | low | never | UI velocityOverride | Per-pad velocity override for DrumKid note pad. |
| `drumkid_hat_closed_vel` | Hat Closed Vel | low | never | UI velocityOverride | Per-pad velocity override for DrumKid note pad. |
| `drumkid_tom_vel` | Tom Vel | low | never | UI velocityOverride | Per-pad velocity override for DrumKid note pad. |
| `dr550_a_01` | A1 (39) | medium | never | MIDI note 39 ch 10 | DR-550 factory pad map: Bank A pad 1. |
| `dr550_a_02` | A2 (56) | medium | never | MIDI note 56 ch 10 | DR-550 factory pad map: Bank A pad 2. |
| `dr550_a_03` | A3 (49) | medium | never | MIDI note 49 ch 10 | DR-550 factory pad map: Bank A pad 3. |
| `dr550_a_04` | A4 (53) | medium | never | MIDI note 53 ch 10 | DR-550 factory pad map: Bank A pad 4. |
| `dr550_a_05` | A5 (37) | medium | never | MIDI note 37 ch 10 | DR-550 factory pad map: Bank A pad 5. |
| `dr550_a_06` | A6 (43) | medium | never | MIDI note 43 ch 10 | DR-550 factory pad map: Bank A pad 6. |
| `dr550_a_07` | A7 (47) | medium | never | MIDI note 47 ch 10 | DR-550 factory pad map: Bank A pad 7. |
| `dr550_a_08` | A8 (50) | medium | never | MIDI note 50 ch 10 | DR-550 factory pad map: Bank A pad 8. |
| `dr550_a_09` | A9 (36) | medium | never | MIDI note 36 ch 10 | DR-550 factory pad map: Bank A pad 9. |
| `dr550_a_10` | A10 (40) | medium | never | MIDI note 40 ch 10 | DR-550 factory pad map: Bank A pad 10. |
| `dr550_a_11` | A11 (42) | medium | never | MIDI note 42 ch 10 | DR-550 factory pad map: Bank A pad 11. |
| `dr550_a_12` | A12 (46) | medium | never | MIDI note 46 ch 10 | DR-550 factory pad map: Bank A pad 12. |
| `dr550_b_01` | B1 (35) | medium | never | MIDI note 35 ch 10 | DR-550 factory pad map: Bank B pad 1. |
| `dr550_b_02` | B2 (38) | medium | never | MIDI note 38 ch 10 | DR-550 factory pad map: Bank B pad 2. |
| `dr550_b_04` | B4 (51) | medium | never | MIDI note 51 ch 10 | DR-550 factory pad map: Bank B pad 4. |
| `dr550_b_05` | B5 (75) | medium | never | MIDI note 75 ch 10 | DR-550 factory pad map: Bank B pad 5. |
| `dr550_b_06` | B6 (41) | medium | never | MIDI note 41 ch 10 | DR-550 factory pad map: Bank B pad 6. |
| `dr550_b_07` | B7 (45) | medium | never | MIDI note 45 ch 10 | DR-550 factory pad map: Bank B pad 7. |
| `dr550_b_08` | B8 (48) | medium | never | MIDI note 48 ch 10 | DR-550 factory pad map: Bank B pad 8. |
| `dr550_b_09` | B9 (85) | medium | never | MIDI note 85 ch 10 | DR-550 factory pad map: Bank B pad 9. |
| `dr550_b_10` | B10 (86) | medium | never | MIDI note 86 ch 10 | DR-550 factory pad map: Bank B pad 10. |
| `dr550_c_01` | C1 (69) | medium | never | MIDI note 69 ch 10 | DR-550 factory pad map: Bank C pad 1. |
| `dr550_c_03` | C3 (68) | medium | never | MIDI note 68 ch 10 | DR-550 factory pad map: Bank C pad 3. |
| `dr550_c_04` | C4 (67) | medium | never | MIDI note 67 ch 10 | DR-550 factory pad map: Bank C pad 4. |
| `dr550_c_05` | C5 (71) | medium | never | MIDI note 71 ch 10 | DR-550 factory pad map: Bank C pad 5. |
| `dr550_c_06` | C6 (64) | medium | never | MIDI note 64 ch 10 | DR-550 factory pad map: Bank C pad 6. |
| `dr550_c_07` | C7 (63) | medium | never | MIDI note 63 ch 10 | DR-550 factory pad map: Bank C pad 7. |
| `dr550_c_08` | C8 (62) | medium | never | MIDI note 62 ch 10 | DR-550 factory pad map: Bank C pad 8. |
| `dr550_c_09` | C9 (61) | medium | never | MIDI note 61 ch 10 | DR-550 factory pad map: Bank C pad 9. |
| `dr550_c_10` | C10 (60) | medium | never | MIDI note 60 ch 10 | DR-550 factory pad map: Bank C pad 10. |
| `dr550_c_11` | C11 (66) | medium | never | MIDI note 66 ch 10 | DR-550 factory pad map: Bank C pad 11. |
| `dr550_c_12` | C12 (65) | medium | never | MIDI note 65 ch 10 | DR-550 factory pad map: Bank C pad 12. |
| `dr550_d_07` | D7 (89) | medium | never | MIDI note 89 ch 10 | DR-550 factory pad map: Bank D pad 7. |
| `dr550_d_08` | D8 (91) | medium | never | MIDI note 91 ch 10 | DR-550 factory pad map: Bank D pad 8. |
| `dr550_d_09` | D9 (84) | medium | never | MIDI note 84 ch 10 | DR-550 factory pad map: Bank D pad 9. |
| `dr550_d_10` | D10 (58) | medium | never | MIDI note 58 ch 10 | DR-550 factory pad map: Bank D pad 10. |

## Drum Controls

- ID: `drumStack`
- Section: `sound`
- Layout: `parameterBoard, min card 180px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `drumkid_cc16_chance` | Chance (CC16) | low | never | MIDI CC 16 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc17_zoom` | Zoom (CC17) | low | never | MIDI CC 17 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc18_range` | Range (CC18) | low | never | MIDI CC 18 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc19_midpoint` | Midpoint (CC19) | low | never | MIDI CC 19 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc20_pitch` | Pitch (CC20) | low | never | MIDI CC 20 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc21_crush` | Crush (CC21) | low | never | MIDI CC 21 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc22_crop` | Crop (CC22) | low | never | MIDI CC 22 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc23_drop` | Drop (CC23) | low | never | MIDI CC 23 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc24_drone` | Drone (CC24) | low | never | MIDI CC 24 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc25_modulate` | Modulate (CC25) | low | never | MIDI CC 25 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc26_tuning` | Tuning (CC26) | low | never | MIDI CC 26 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc27_note` | Note (CC27) | low | never | MIDI CC 27 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. CC27 is 'Note' but regular note commands are preferred. |
| `drumkid_cc28_beat` | Beat (CC28) | low | never | MIDI CC 28 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc29_beats_bar` | Beats/Bar (CC29) | low | never | MIDI CC 29 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc30_swing` | Swing (CC30) | low | never | MIDI CC 30 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. |
| `drumkid_cc31_tempo` | Tempo (CC31) | low | never | MIDI CC 31 ch 10 | DrumKid responds to CC 16-31 on any channel; sent on Ch 10 for drum stack. CC31 (Tempo) ignored when DrumKid is synced to external clock. |

## Synth

- ID: `electribe`
- Section: `sound`
- Layout: `parameterBoard, min card 180px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `electribe_pattern` | Pattern # | low | never | MIDI program ch 11 | Electribe pattern select (1-127) with bank toggle A/B. |
| `electribe_bank_a` | Bank A | low | never | UI patternBank | Electribe pattern bank A (LSB 0). |
| `electribe_bank_b` | Bank B | low | never | UI patternBank | Electribe pattern bank B (LSB 1). |
| `electribe_scene_1` | Scene 1 | high | never | MIDI program ch 11 | Quick scene (pattern) select; uses current bank. |
| `electribe_scene_2` | Scene 2 | high | never | MIDI program ch 11 | Quick scene (pattern) select; uses current bank. |
| `electribe_scene_3` | Scene 3 | high | never | MIDI program ch 11 | Quick scene (pattern) select; uses current bank. |
| `electribe_scene_4` | Scene 4 | high | never | MIDI program ch 11 | Quick scene (pattern) select; uses current bank. |
| `electribe_cc7` | Amp Level (CC7) | low | never | MIDI CC 7 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc10` | Amp Pan (CC10) | low | never | MIDI CC 10 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc74` | Filter Cutoff (CC74) | low | never | MIDI CC 74 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc71` | Filter Resonance (CC71) | low | never | MIDI CC 71 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc73` | EG Attack (CC73) | low | never | MIDI CC 73 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc72` | EG Decay/Release (CC72) | low | never | MIDI CC 72 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc83` | Filter EG Int (CC83) | low | never | MIDI CC 83 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc80` | Osc Pitch (CC80) | low | never | MIDI CC 80 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc81` | Osc Glide (CC81) | low | never | MIDI CC 81 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc82` | Osc Edit (CC82) | low | never | MIDI CC 82 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc85` | Modulation Depth (CC85) | low | never | MIDI CC 85 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc86` | Modulation Speed (CC86) | low | never | MIDI CC 86 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc87` | Insert FX Edit (CC87) | low | never | MIDI CC 87 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc102` | Master FX X (CC102) | low | never | MIDI CC 102 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc103` | Master FX Y (CC103) | low | never | MIDI CC 103 ch 11 | Electribe 2S panel control CC. |
| `electribe_cc104` | Insert FX On/Off (CC104) | low | never | MIDI CC 104 ch 11 | Electribe 2S panel control on/off (0=Off, 127=On). |
| `electribe_cc105` | MFX Send On/Off (CC105) | low | never | MIDI CC 105 ch 11 | Electribe 2S panel control on/off (0=Off, 127=On). |
| `electribe_cc106` | Master FX On/Off (CC106) | low | never | MIDI CC 106 ch 11 | Electribe 2S panel control on/off (0=Off, 127=On). |

## MSVP

- ID: `msvp`
- Section: `video`
- Layout: `parameterBoard, min card 180px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `vid_scene_intro` | Scene Intro | high | ttl | OSC /video/scene/intro | scene.intro from live-rig controller export. Canonical MIDI fallback is ch 10 note 60. Generated from the committed live-rig snapshot mirror. |
| `vid_scene_crash` | Scene Crash | high | ttl | OSC /video/scene/crash | scene.crash from live-rig controller export. Canonical MIDI fallback is ch 10 note 61. Generated from the committed live-rig snapshot mirror. |
| `vid_scene_soft` | Scene Soft | high | ttl | OSC /video/scene/soft | scene.soft from live-rig controller export. Canonical MIDI fallback is ch 10 note 62. Generated from the committed live-rig snapshot mirror. |
| `vid_scene_clean_camera` | Clean Camera | high | ttl | OSC /video/scene/clean_camera | scene.clean_camera from live-rig controller export. Canonical MIDI fallback is ch 10 note 64. Generated from the committed live-rig snapshot mirror. |
| `vid_state_blackout` | Blackout | critical | safety | OSC /rig/state/blackout | state.blackout from live-rig controller export. Canonical MIDI fallback is ch 10 note 63. Generated from the committed live-rig snapshot mirror. |
| `rig_state_manual_override` | Manual Override | high | ttl | OSC /rig/state/manual_override | state.manual_override from live-rig controller export. Canonical MIDI fallback is ch 10 cc 64. Generated from the committed live-rig snapshot mirror. |
| `macro_analysis_blend` | Analysis Blend | medium | latest | OSC /macro/analysis_blend | macro.analysis_blend from live-rig controller export. Generated from the committed live-rig snapshot mirror. |
| `msvp_macro_lines_per_frame` | Macro Density (CC1) | low | never | MIDI CC 1 ch 10 | MSVP macro lane. Canonical param linesPerFrame, OSC equivalent /msvp/macro/linesPerFrame. |
| `msvp_macro_max_line_size` | Macro Line Size (CC2) | low | never | MIDI CC 2 ch 10 | MSVP macro lane. Canonical param maxLineSize, OSC equivalent /msvp/macro/maxLineSize. |
| `msvp_macro_opacity_min` | Macro Opacity Floor (CC3) | low | never | MIDI CC 3 ch 10 | MSVP macro lane. Canonical param opacityMin, OSC equivalent /msvp/macro/opacityMin. |
| `msvp_macro_effect_interval_beats` | Macro FX Interval (CC4) | low | never | MIDI CC 4 ch 10 | MSVP macro lane. Canonical param effectIntervalBeats, OSC equivalent /msvp/macro/effectIntervalBeats. |
| `msvp_macro_effect_duration_beats` | Macro FX Duration (CC5) | low | never | MIDI CC 5 ch 10 | MSVP macro lane. Canonical param effectDurationBeats, OSC equivalent /msvp/macro/effectDurationBeats. |
| `msvp_macro_bpm_smoothing` | Macro BPM Smooth (CC6) | low | never | MIDI CC 6 ch 10 | MSVP macro lane. Canonical param bpmSmoothing, OSC equivalent /msvp/macro/bpmSmoothing. |
| `msvp_macro_effect_bias` | Macro FX Bias (CC7) | low | never | MIDI CC 7 ch 10 | MSVP macro lane. Canonical param effectBias, OSC equivalent /msvp/macro/effectBias. |
| `msvp_analysis_lines_per_frame` | Analysis Density Bias (CC1) | low | never | MIDI CC 1 ch 15 | MSVP analysis lane. Canonical param linesPerFrame, OSC equivalent /msvp/analysis/linesPerFrame. |
| `msvp_analysis_max_line_size` | Analysis Line Size Bias (CC2) | low | never | MIDI CC 2 ch 15 | MSVP analysis lane. Canonical param maxLineSize, OSC equivalent /msvp/analysis/maxLineSize. |
| `msvp_analysis_opacity_min` | Analysis Opacity Bias (CC3) | low | never | MIDI CC 3 ch 15 | MSVP analysis lane. Canonical param opacityMin, OSC equivalent /msvp/analysis/opacityMin. |
| `msvp_analysis_effect_interval_beats` | Analysis FX Interval Bias (CC4) | low | never | MIDI CC 4 ch 15 | MSVP analysis lane. Canonical param effectIntervalBeats, OSC equivalent /msvp/analysis/effectIntervalBeats. |
| `msvp_analysis_effect_duration_beats` | Analysis FX Duration Bias (CC5) | low | never | MIDI CC 5 ch 15 | MSVP analysis lane. Canonical param effectDurationBeats, OSC equivalent /msvp/analysis/effectDurationBeats. |
| `msvp_analysis_bpm_smoothing` | Analysis BPM Smooth (CC6) | low | never | MIDI CC 6 ch 15 | MSVP analysis lane. Canonical param bpmSmoothing, OSC equivalent /msvp/analysis/bpmSmoothing. |
| `msvp_analysis_effect_bias` | Analysis FX Bias (CC7) | low | never | MIDI CC 7 ch 15 | MSVP analysis lane. Canonical param effectBias, OSC equivalent /msvp/analysis/effectBias. |

## Video Feed

- ID: `nwWrldFeed`
- Section: `video`
- Layout: `mappedGrid`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `nw_feed_enable` | nw_wrld On | medium | ttl | OSC /nw_wrld/feed/enable | Bridge this to SC Video Mixer input enable for the nw_wrld feed. |
| `nw_feed_blackout` | Blackout | critical | safety | OSC /nw_wrld/feed/blackout | Hard kill for the nw_wrld feed or mixer layer. |
| `nw_scene_intro` | Scene: Intro | high | ttl | OSC /nw_wrld/scene/intro |  |
| `nw_scene_crash` | Scene: Crash | high | ttl | OSC /nw_wrld/scene/crash |  |
| `nw_scene_soft` | Scene: Soft | high | ttl | OSC /nw_wrld/scene/soft |  |
| `nw_mix_clean` | Mix: Clean | medium | ttl | OSC /nw_wrld/mix/clean | Intended to bias toward unprocessed nw_wrld feed in the mixer. |
| `nw_mix_processed` | Mix: Processed | medium | ttl | OSC /nw_wrld/mix/processed | Intended to bias toward processed/feedback chain. |
| `nw_key_enable` | Key On | medium | ttl | OSC /nw_wrld/key/enable | Key on/off in SC Video Mixer if used. |
| `nw_fx_feedback` | FX: Feedback | medium | ttl | OSC /nw_wrld/fx/feedback |  |
| `nw_overlay_text` | Overlay: Text | medium | ttl | OSC /nw_wrld/overlay/text |  |
| `nw_overlay_grid` | Overlay: Grid | medium | ttl | OSC /nw_wrld/overlay/grid |  |
| `nw_overlay_mask` | Overlay: Mask | medium | ttl | OSC /nw_wrld/overlay/mask |  |

## FX Macros

- ID: `pcm30Macros`
- Section: `video`
- Layout: `parameterBoard, min card 180px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `pcm30_f1_xfade` | F1 XFade (CC1) | low | never | MIDI CC 1 ch 11 |  |
| `pcm30_f2_fb` | F2 FB Feedback (CC2) | low | never | MIDI CC 2 ch 11 |  |
| `pcm30_f3_mosh` | F3 Mosh (CC3) | low | never | MIDI CC 3 ch 11 |  |
| `pcm30_f4_mael` | F4 Maelstrom (CC4) | low | never | MIDI CC 4 ch 11 |  |
| `pcm30_f5_retrace` | F5 ReTrace (CC5) | low | never | MIDI CC 5 ch 11 |  |
| `pcm30_f6_contrast` | F6 Contrast (CC6) | low | never | MIDI CC 6 ch 11 |  |
| `pcm30_f8_blackout` | F8 Blackout (CC8) | critical | safety | MIDI CC 8 ch 11 |  |
| `pcm30_k1_glitch` | K1 Fine Glitch (CC21) | low | never | MIDI CC 21 ch 11 |  |
| `pcm30_k2_fb` | K2 Fine FB (CC22) | low | never | MIDI CC 22 ch 11 |  |
| `pcm30_k3_warp` | K3 Warp (CC23) | low | never | MIDI CC 23 ch 11 |  |
| `pcm30_k4_wire` | K4 Wireframe (CC24) | low | never | MIDI CC 24 ch 11 |  |
| `pcm30_k5_texture` | K5 Texture (CC25) | low | never | MIDI CC 25 ch 11 |  |
| `pcm30_k6_blend` | K6 frZone Blend (CC26) | low | never | MIDI CC 26 ch 11 |  |
| `pcm30_k7_hue` | K7 Hue (CC27) | low | never | MIDI CC 27 ch 11 |  |
| `pcm30_k8_spare` | K8 Spare (CC28) | low | never | MIDI CC 28 ch 11 |  |
| `pcm30_scene_crash` | Scene Crash (Note60) | high | never | MIDI note 60 ch 11 |  |
| `pcm30_scene_soft` | Scene Soft (Note61) | high | never | MIDI note 61 ch 11 |  |
| `pcm30_blackout` | Blackout (Note62) | critical | safety | MIDI note 62 ch 11 |  |

## Video Input

- ID: `nwWrldInput`
- Section: `video`
- Layout: `mappedGrid`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `nw_track_1` | Track 1 | medium | never | MIDI note 12 ch 1 |  |
| `nw_track_2` | Track 2 | medium | never | MIDI note 13 ch 1 |  |
| `nw_track_3` | Track 3 | medium | never | MIDI note 14 ch 1 |  |
| `nw_track_4` | Track 4 | medium | never | MIDI note 15 ch 1 |  |
| `nw_track_5` | Track 5 | medium | never | MIDI note 16 ch 1 |  |
| `nw_track_6` | Track 6 | medium | never | MIDI note 17 ch 1 |  |
| `nw_track_7` | Track 7 | medium | never | MIDI note 18 ch 1 |  |
| `nw_track_8` | Track 8 | medium | never | MIDI note 19 ch 1 |  |
| `nw_ch_1` | Ch 1 | medium | never | MIDI note 112 ch 2 |  |
| `nw_ch_2` | Ch 2 | medium | never | MIDI note 113 ch 2 |  |
| `nw_ch_3` | Ch 3 | medium | never | MIDI note 114 ch 2 |  |
| `nw_ch_4` | Ch 4 | medium | never | MIDI note 115 ch 2 |  |
| `nw_ch_5` | Ch 5 | medium | never | MIDI note 116 ch 2 |  |
| `nw_ch_6` | Ch 6 | medium | never | MIDI note 117 ch 2 |  |
| `nw_ch_7` | Ch 7 | medium | never | MIDI note 118 ch 2 |  |
| `nw_ch_8` | Ch 8 | medium | never | MIDI note 119 ch 2 |  |
| `nw_ch_9` | Ch 9 | medium | never | MIDI note 120 ch 2 |  |
| `nw_ch_10` | Ch 10 | medium | never | MIDI note 121 ch 2 |  |
| `nw_ch_11` | Ch 11 | medium | never | MIDI note 122 ch 2 |  |
| `nw_ch_12` | Ch 12 | medium | never | MIDI note 123 ch 2 |  |
| `nw_ch_13` | Ch 13 | medium | never | MIDI note 124 ch 2 |  |
| `nw_ch_14` | Ch 14 | medium | never | MIDI note 125 ch 2 |  |
| `nw_ch_15` | Ch 15 | medium | never | MIDI note 126 ch 2 |  |
| `nw_ch_16` | Ch 16 | medium | never | MIDI note 127 ch 2 |  |
| `nw_track_9` | Track 9 | medium | never | MIDI note 20 ch 1 |  |
| `nw_track_10` | Track 10 | medium | never | MIDI note 21 ch 1 |  |

## Controller Slots

- ID: `mn42Slots`
- Section: `setup`
- Layout: `parameterBoard, min card 120px`

| Pad | Label | Risk | Queue | Transport | Notes |
| --- | --- | --- | --- | --- | --- |
| `mn42_slot_01` | S01 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_02` | S02 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_03` | S03 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_04` | S04 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_05` | S05 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_06` | S06 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_07` | S07 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_08` | S08 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_09` | S09 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_10` | S10 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_11` | S11 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_12` | S12 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_13` | S13 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_14` | S14 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_15` | S15 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_16` | S16 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_17` | S17 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_18` | S18 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_19` | S19 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_20` | S20 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_21` | S21 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_22` | S22 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_23` | S23 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_24` | S24 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_25` | S25 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_26` | S26 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_27` | S27 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_28` | S28 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_29` | S29 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_30` | S30 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_31` | S31 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_32` | S32 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_33` | S33 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_34` | S34 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_35` | S35 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_36` | S36 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_37` | S37 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_38` | S38 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_39` | S39 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_40` | S40 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_41` | S41 | low | latest | OSC /mn42/cmd |  |
| `mn42_slot_42` | S42 | low | latest | OSC /mn42/cmd |  |
