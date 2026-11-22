---
name: unity-project-workflow
description: How to add or change code, scenes, packages, and assets in the EMP Escape Unity 6 project, plus editor gotchas already hit and a C# syntax checker. Load before adding scripts or packages, regenerating the test scene, or debugging Unity editor problems.
---

# Unity project workflow

## Adding code
- Runtime scripts go in `Assets/EMPEscape/Scripts/`, namespace `EMPEscape`. Editor-only tools go in `Assets/EMPEscape/Editor/`, namespace `EMPEscape.EditorTools`.
- One system or component per file. Use singletons (`Instance`) only for scene-level directors (`StoryDirector`, `CameraDirector`, `GameUI`, `PlayerController`).
- Build UI through `UIFactory` helpers (`NewRect`, `Panel`, `Label`, `MakeButton`, `Stretch`, `Center`, `Anchor`). Don't name helpers `Rect` or `Button`; they collide with Unity types.
- Read taps with `GameInput.PressedThisFrame` / `IsPressed` / `IsOverUI`. Lock world input during story with `GameInput.Lock()` / `Unlock()`.
- Movement: `PlayerController` = floating virtual stick (drag, drawn by `JoystickUI`) + tap-to-move/tap-hotspot. The stick keeps its camera basis until release, so camera cuts don't flip direction. Tune `dragThreshold`, `stickRadius`, `deadZone`, `minSpeedFraction` on the Player.
- Story output goes through `IStoryPresenter`: `DialogueUI` (subtitles) by default, `CommsApp` (phone chat) via `StoryDirector.RunKnot(knot, presenter)`.
- HUD (`HudUI`, bottom right): PHONE and LIGHT once Ink `has_phone`, CHOICES always. Overlays (phone, choices) call `GameInput.Lock()` while open.
- Camera zones nest: the zone entered last wins and leaving it returns to the zone around it (a shed inside a yard zone).
- Characters: every character root has a `CharacterActor` (`actorName` matches the Ink speaker). Without a clip, `Play("flinch")` wobbles the visual so placeholders react to hits. See the art-asset-pipeline skill for animation.
- Actions: `QTEController` runs tap/mash/hold/shoot/swing; `QTESpec` parses the Ink tag. `ShootTarget` (group name) marks shootable things; `WeaponHolder` on the player shows the prop for Ink's `weapon`. Feel knobs: `hitRadius`, `sway`, `knifeSwipe`, `batSwipe`, `swipeTolerance` on the QTE component (added at runtime, so change defaults in code).
- No asmdef files in `Assets/EMPEscape` yet; scripts compile into Assembly-CSharp, which auto-references the Ink (`Ink`, `Ink-Libraries`) and AI Navigation assemblies.

## Scene
- Two generated scenes: `Slice.unity` (**Build Test Slice Scene**, `SliceSceneBuilder.cs`) and `Sandbox.unity` (**Build Action Sandbox**, `SandboxSceneBuilder.cs`). Both use `SceneBuildKit.cs` via `using static` (BeginScene, MakePlayer, MakeNpc, Block, Vehicle, WeaponProp, ShootingTarget, Hotspot, Anchor, Zone, SetupCamera, SetupGame, FinishScene).
- To change a scene, edit its builder and re-run the menu item. Hand edits to scenes are lost on rebuild.
- Each build puts its scene first in Build Settings: the scene built last is what launches on the iPhone.
- Adding a sandbox station: geometry in `Yard` (walkable/blocking) or `Props` (tappable, not in the NavMesh), a `Hotspot` + stand point, a close-up camera anchor, and knots in `sandbox.ink`.
- Object roots carry the colliders (vehicles/characters at ground level, blocks at their center). Visuals are child objects: placeholder primitives or models from `SliceArtSet`. Never put colliders on visuals.
- Camera anchors referenced by Ink `# cam:` tags must exist as children of `CameraAnchors`.

## Packages
- Install from **Window > Package Manager** (inside the Unity editor, not Unity Hub). Git packages: **+ > Install package from git URL**.
- Install packages **before** copying in scripts that use them, or Unity opens in Safe Mode with compile errors.
- Current packages: Ink (`https://github.com/inkle/ink-unity-integration.git#upm`), AI Navigation, Input System.

## Checking C# without Unity
Agents can't compile against Unity, but can catch syntax errors with the tree-sitter checker in `scripts/check_csharp.mjs`.
Install deps outside the project, then run it from the project root:
```
mkdir -p ~/cscheck && (cd ~/cscheck && npm install web-tree-sitter@latest tree-sitter-c-sharp)
cp .claude/skills/unity-project-workflow/scripts/check_csharp.mjs ~/cscheck/check.mjs
node ~/cscheck/check.mjs Assets/EMPEscape/Scripts/*.cs Assets/EMPEscape/Editor/*.cs
```
Syntax only: wrong Unity API names still need the owner's Console. Review API names carefully.

## Delivering files to the owner
- If the device bridge to the Mac is available, write directly into `/Users/bruce.frick/Desktop/unity-game`.
- Otherwise send a zip that unpacks at the project root (`Assets/EMPEscape/...`) with `unzip -o`.

## Repo hygiene
- The project is a git repo. Commit `.claude/`, `AGENTS.md`, `CLAUDE.md` with the code; untracked skills were lost once during a folder reshuffle.
- `__previous__/` is the retired RealityKit project. Don't edit or build it.
- A Unity `.gitignore` should exclude `Library/`, `Temp/`, `Logs/`, `UserSettings/`, `obj/`, `*.csproj`, `*.slnx`, and `ios-game/`. Ask the owner before changing what git tracks.

## Gotchas already hit
| Problem | Cause and fix |
|---|---|
| Builder said `chapter1_slice.json` not found | The Ink package stores compiled JSON inside the `InkFile` asset; there is no `.json`. Load `InkFile` and use `storyJson` |
| macOS "no application set to open chapter1_slice.ink" | Double-clicking opens it externally. Single-click and use the Inspector, or install Inky |
| "Unable to open ...: Check external application preferences" warning | Harmless leftover from a double-click |
| Build blocked by importing/compiling | Wait for the spinner; check Console for red errors |
| `GetComponent<T>() ?? AddComponent<T>()` adds nothing in the editor | Unity returns a fake-null object for missing components. Use `if (x == null)` with Unity objects, never `??` or `?.` |
| `Random` is ambiguous in a file with `using System;` | Write `UnityEngine.Random`, or alias `using Object = UnityEngine.Object;` for Object |
| Method-group LINQ like `.Select(AssetDatabase.GUIDToAssetPath)` | Overloaded methods can break type inference. Use a lambda |
Add new gotchas here as they're found.
