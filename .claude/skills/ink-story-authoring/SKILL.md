---
name: ink-story-authoring
description: How EMP Escape's Ink story files are written and read by the game - tag conventions (cam, timer, remember, qte, anim, end), knot naming for hotspots, flags, and how to compile-check. Load before writing or editing any .ink file.
---

# Ink story authoring

Story files live in `Assets/EMPEscape/Ink/`. `StoryDirector.cs` runs one knot at a time.

## Conventions the game reads
| Write in Ink | Game does |
|---|---|
| `Ray: Some line.` | Speaker label "Ray". Speaker = capitalized, up to 25 chars, then `: ` |
| `# cam: ray_close` | Hard cut to that camera anchor (a child of `CameraAnchors` in the scene) |
| `# timer: 7` | On the **last line before choices**. Timed choice; the **last** choice is auto-picked on timeout, so make it the silence option |
| `# remember: Ray will remember that.` | Top-left toast |
| `# qte: tap 1.5` / `mash 3 7` / `hold 3 1.5` | Runs a QTE (type, window seconds, presses or hold seconds), then picks the choice whose text is exactly `success` or `fail` |
| `# anim: Ray flinch` | Fires the `Flinch` trigger on the CharacterActor named Ray (actor, space, action). Current actions: flinch |
| `# end` | After the knot finishes, shows the end screen with Restart |
Speakers with a matching `CharacterActor` play their talk animation automatically while their line is on screen.
Unknown tags log a warning. Add new tags in `StoryDirector.HandleTags` and document them here.

## Knot rules
- Hotspot knots are named `<object>_<verb>` (`car_look`, `ray_talk`, `overpass_use`) and set on the object's `Hotspot` component.
- Every hotspot knot ends with `-> END`. The game returns control to the player when the knot ends.
- At most 4 choices per decision (the UI shows 4).
- QTE choices must be exactly `* [success]` and `* [fail]`.
- Declare all flags with `VAR` at the top of the file. Use names like `ray_trust`, `has_bag`, `talked_to_ray`.
- Repeat visits: guard with a flag (`{ talked_to_ray: -> again }`) so conversations don't replay from the start.
- Game code reads flags with `StoryDirector.Instance.GetInt("ray_trust")` / `GetBool(...)`.

## How the compiled story is stored
The Ink package compiles each master `.ink` into an `InkFile` asset (the `.ink` file itself). There is **no
separate `.json` file**. Code loads it as `InkFile` and uses `inkFile.storyJson`. In the editor, single-click the
`.ink` file and check the Inspector for "Last compile" and errors (double-clicking opens it externally).

## Compile check (agents without Unity)
Install inkjs outside the project so no `node_modules` lands in `Assets/`, then run from the project root:
```
mkdir -p ~/inkjs-tools && (cd ~/inkjs-tools && npm install inkjs)
NODE_PATH=~/inkjs-tools/node_modules node .claude/skills/ink-story-authoring/scripts/check_ink.js Assets/EMPEscape/Ink/chapter1_slice.ink
```
It compiles the file, then runs every knot taking the first choice, printing each line with its tags.
It ends with `OK`; a compile or runtime error exits non-zero.
