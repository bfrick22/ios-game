---
name: art-asset-pipeline
description: How EMP Escape gets real art and animation - Kenney CC0 kits (Car Kit, City Kit, Animated Characters) rigged through Mixamo, the Assets/EMPEscape/Art folder conventions, import rules, the generated character animator, and how the scene builder swaps models in. Load before adding, replacing, or debugging models, characters, or animations.
---

# Art asset pipeline (Kenney + Mixamo)

Agents can't download these (kenney.nl and mixamo.com are blocked, and Mixamo needs an Adobe login).
Give the owner the download steps; the code side is automatic.

## Current art (Nov 2026)
- Characters: `player.fbx`, `ray.fbx` (Kenney Animated Character rigged in Mixamo).
- Animations: `idle`, `walk`, `talk`, `flinch` (plus unused `run`, `run-flip`).
- Vehicles: Kenney Car Kit. City: Kenney **City Kit Suburban** (houses `building-type-a..u`, fences, trees, planters, paths; no lamps).

## Folders (under `Assets/EMPEscape/Art/`)
| Folder | What goes in | Import rule (ArtImportRules.cs, first import only) |
|---|---|---|
| `Characters/` | Mixamo-rigged characters, FBX for Unity, T-pose (the character download always includes skin) | Humanoid rig, avatar from model |
| `Animations/` | Humanoid animation FBX: Mixamo (one clip per file, **without skin**) or a multi-clip library such as Quaternius UAL. File or clip names must contain idle / walk / talk (or conversation) / flinch (or hit, react) | Humanoid; single clips renamed to the file; clips with idle/walk/talk/run loop; root locked |
| `Vehicles/` | Kenney Car Kit FBX files plus their `Textures/` folder | Unity defaults |
| `City/` | Kenney City Kit FBX files plus `Textures/` | Unity defaults |

## Owner's download steps
1. **Kenney packs** (free, CC0) from kenney.nl. Use the files in each pack's FBX folder and keep the `Textures` folder next to them.
2. **Rig a character in Mixamo:** sign in, **Upload Character**, drop a Kenney character FBX. If the Auto-Rigger opens: face it forward, place chin/wrist/elbow/knee/groin markers, Standard Skeleton (65). Download with no animation selected: **FBX for Unity**, **T-pose**. Copy it as `Player.fbx` and `Ray.fbx`.
3. **Animations in Mixamo**, on that character: **FBX for Unity**, **Without Skin**. Tick **In Place** for walking. Name them `idle.fbx`, `walk.fbx`, `talk.fbx`, `flinch.fbx`.
4. Drag files into the folders above in Unity's Project window.
5. Run **EMP Escape > Build Character Animator**, then **EMP Escape > Build Test Slice Scene**.

## If Mixamo won't load
Mixamo has frequent login and loading problems even when its status is green. Try: sign in at adobe.com first,
then open mixamo.com in a private window or another browser with ad blockers off. If it still fails, use
Quaternius (CC0, no login): a base character plus the Universal Animation Library, both on a humanoid rig.
Characters go in `Characters/`, the library FBX in `Animations/`; clip names are matched by keyword.

## How the builder uses art
- `Art/SliceArtSet.asset` holds the picks. Empty slots auto-fill by file name each build:
  player (`player` or first character), ray (`ray` or second), van (`delivery`, `van`), truck (`truck`, `garbage-truck`, `box`),
  your car (`sedan`, `hatchback`, `suv`, `coupe`), parked cars (other road cars), buildings (`building`, `skyscraper`, `house`, `shop`...), props (`light`, `lamp`, `hydrant`, `bench`, `sign`, `tree`, `planter`...).
- Exact file-name matches win over partial ones (`truck.fbx` beats `firetruck.fbx`). Parked cars skip karts, race cars, tractors, fire and garbage trucks, wheels, debris and cones.
- After changing pick rules or adding models, run **EMP Escape > Reset Art Picks** (otherwise only empty slots auto-fill), then rebuild the scene.
- Override a pick by dragging a different model into the slot in the Inspector. Fix sideways/backwards models with `vehicleYawOffset` / `characterYawOffset`.
- Colliders and the NavMesh never change with art. Models are visual children, auto-scaled (characters 1.8 m tall, vehicles to the gameplay box length, buildings ~8 m wide, props 4.5 m tall) and set on the ground.
- Buildings and props go in `Backdrop`, outside the barriers, not walkable.

## Character animation
- `CharacterAnimatorBuilder` makes `Art/EMPCharacter.controller`: Idle (default), Walk (Speed > 0.1), Talk (Talking bool), Flinch (trigger, from any state).
- `CharacterActor` (on each character root, `actorName` = Ink speaker name) drives Speed from movement, sets Talking while that character's line is on screen, and fires triggers from Ink `# anim: Ray flinch`.
- New one-shot action (e.g. `point`): add the clip to `Animations/`, add a role + trigger + state in `CharacterAnimatorBuilder`, rebuild the animator and scene, then use `# anim: Ray point`.

## Problems and fixes
| Problem | Fix |
|---|---|
| Characters T-pose | No idle clip found, or the animator wasn't rebuilt. Check `Art/Animations` names, run Build Character Animator, rebuild the scene |
| Character slides instead of walking | Walk clip missing, or not downloaded **In Place** |
| Pink models | Materials not URP. Select them > Edit > Rendering > Materials > Convert Selected Built-in Materials to URP |
| Untextured grey Kenney models | The pack's `Textures` folder wasn't copied next to the FBX files |
| Vehicle sideways | Set `vehicleYawOffset` (90 or -90) in SliceArtSet, rebuild scene |
| Mixamo download dialog shows no Skin option | Normal when no animation is selected: the T-pose character download always includes the skin |
| Avatar errors on a Kenney character | Rig it through Mixamo first (step 2) |
