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
| `# qte: shoot 7 range` | Shoot QTE: window seconds, then the `ShootTarget` group to clear. Rounds = targets + 2. Cut to a camera that shows the targets first |
| `# qte: swing 1.2 3 Dummy` | Swing QTE: seconds per swing, number of swings, optional CharacterActor that flinches on each hit. Swipe length depends on the held weapon |
| `# anim: Ray flinch` | Fires a one-shot on the CharacterActor named Ray (actor, space, action). Actions: flinch, swing, shoot |
| `# reset: stranger` | Stands a ShootTarget group back up |
| `# death: You didn't make it.` | After the knot finishes, shows the death screen. Retry restores the story to the start of the knot and replays it |
| `# sfx: door_bang` / `# ambience: amb_wind, amb_birds` / `# distant: distant_shot` | Sound (audio-pipeline skill) |
| `# decision: ray_answer = coming, You told Ray you're coming.` | Saves a decision across sessions (key = value, then the text for the CHOICES list). Same key replaces. Ink tags can't contain `\|` |
| `# note: Ray is heading north at dark.` | Adds a note to the phone's Notes app |
| `# end` / `# end: End of sandbox` | After the knot finishes, shows the end screen (optional title) with Restart |
Speakers with a matching `CharacterActor` play their talk animation automatically while their line is on screen.
Unknown tags log a warning. Add new tags in `StoryDirector.HandleTags` and document them here.

## Weapon variable
Declare `VAR weapon = "none"` to use weapons. The game watches it and puts the prop in the player's hand
(`none`, `knife`, `bat`, `pistol`), so picking up is just `~ weapon = "bat"`. Branch on it with
`{ weapon: - "knife": -> knife_fight - else: -> bare_hands }`. Stories without the variable ignore weapons.

## Remembered decisions
Declare the external with a fallback (the fallback is used by Inky and the checker; the game binds the real one):
```
EXTERNAL decided(key)
=== function decided(key) ===
~ return ""
```
Then `~ temp before = decided("ray_answer")` and branch on it with `{ before: - "coming": ... - "": ... - else: ... }`.

## Phone variables and chats
`has_phone`, `phone_battery`, `pack_<id>`, `net_<id>`: see the phone skill. Comms chats are ordinary knots
shown as messages: `BASECAMP: text` arrives, `You: text` is sent, plain lines are system notes, choices are
replies (no quotes around them).

## Knot rules
- Hotspot knots are named `<object>_<verb>` (`car_look`, `ray_talk`, `overpass_use`) and set on the object's `Hotspot` component.
- Every hotspot knot ends with `-> END`. The game returns control to the player when the knot ends.
- At most 4 choices per decision (the UI shows 4).
- An if / else-if chain with several conditions starts with `{` on its own line, each branch `- condition:`. `{ a: ... - b: ... }` on one line is read as a switch and fails.
- QTE choices must be exactly `* [success]` and `* [fail]`. Put a divert on its own line after text (`* [success] He drops.` then `    -> won`); `text -> won` on one line glues the next line onto it.
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
