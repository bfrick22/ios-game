---
name: audio-pipeline
description: How EMP Escape plays sound - AudioDirector (one-shots, ambience beds, distant events), AmbientEmitter, the Resources/Audio naming convention, Ink sound tags, and the numpy synthesizer that makes placeholder WAVs. Load before adding, replacing, or debugging any sound.
---

# Audio pipeline

## How it works
- Every clip lives in `Assets/EMPEscape/Resources/Audio/` and is played **by file name** (no extension). A real
  recording replaces a placeholder by taking its name (wav, ogg or mp3; delete the old file).
- `AudioDirector` (static API, creates itself on first use):
  - `Play(name, volume, pitchJitter)`: 2D one-shot. `PlayAt(name, position, ...)`: placed in the world (70% 3D, since the camera hears from far away).
  - `SetAmbience("amb_wind, amb_birds")`: crossfades looping beds (2 s). `"none"` = silence.
  - `SetDistant("distant_shot, distant_crash")`: a random one from the list every 20-50 s, panned randomly. `"none"` stops.
  - Volume knobs: `effectsVolume`, `ambienceVolume`, `distantVolume`.
- `AmbientEmitter` (scene builder adds it): a looping 3D sound at a spot (burn barrel `fire_crackle`).
- The AudioListener is on the main camera.

## From Ink
| Tag | Does |
|---|---|
| `# sfx: door_bang` | One-shot |
| `# ambience: amb_wind, amb_birds` | Set the beds (put it on a scene's opening line) |
| `# distant: distant_shot, distant_crash` | Set the random distant events |

## Hooked up in code (no tag needed)
| Event | Sound |
|---|---|
| Any button | `ui_tap` (UIFactory.MakeButton) |
| Player walking | `step_1..4` every 0.75 m (CharacterActor.footsteps, on for the player) |
| QTE press / success / fail | `qte_press`, `qte_success`, `qte_fail` |
| Shot / target hit | `gunshot`, `ShootTarget.hitSound` (`target_hit` plates, `hit_flesh` people) |
| Swing | `knife_slash` or `swing_whoosh`, then `hit_flesh` |
| Remember toast / death | `remember_chime`, `death_sting` |
| Phone | `ui_open`, `ui_close`, `ui_type`, `device_beep`, `device_error`, `msg_in`, `msg_out`, `camera_shutter`, `light_click` |

## Placeholder sounds
Synthesized with numpy, no downloads: `scripts/synth_placeholders.py`. From the project root:
```
python3 .claude/skills/audio-pipeline/scripts/synth_placeholders.py                      # all
python3 .claude/skills/audio-pipeline/scripts/synth_placeholders.py --only=gunshot,msg_in # some
```
Add a sound: write a function returning a numpy array (helpers: `white`, `band`, `tone`, `env_exp`, `reverb`,
`place`, `make_loop`, `finish`), add it to `SOUNDS`, run with `--only`. Loops must use `finish(..., loop=True)`
(an end fade would click at the seam). Check seams and levels with a quick numpy read of the WAV.

## Replacing with real recordings
Free sources: Kenney audio packs (CC0: UI, impacts), Sonniss GDC bundles (royalty-free). Keep names, keep
loops seamless, mono is fine for one-shots. Voice acting will be a separate system (not built yet).
