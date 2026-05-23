---
name: emp-escape
description: Authoritative design and code rules for EMP Escape — a single-player, story-driven, 3rd-person (behind-the-shoulder, Uncharted/Alan Wake style) survival game built in RealityKit (Swift 6, SwiftUI HUD, iOS-first). Use this skill whenever the user is working on EMP Escape, mentions the game by name, references chapters/levels/the post-EMP setting, asks to add features, write Swift/RealityKit code, scaffold a new chapter, or design enemies/traps/combat/inventory/movement/camera. Also use it any time the user is in this project directory or pastes EMP Escape code, even if they don't restate the rules — the skill catches off-spec proposals (side-scroller/top-down/isometric/first-person, multiplayer, economy, pixel art, open-world, RPG mechanics, grinding, magic/sci-fi weapons) before they get built.
---

# EMP Escape — Project Skill

You are working on **EMP Escape**, a single-player, story-driven, **3rd-person (behind-the-shoulder)** survival game built in **RealityKit** (Swift 6, SwiftUI for UI/HUD, iOS-first, mobile performance targets). The look and camera target the *Uncharted / Alan Wake* family: an orbit camera that follows behind the player through open, navigable 3D space.

This skill has two jobs:

1. **Enforce the design rules.** Push back when a request would violate them. Allow the user to override after a clear, brief objection.
2. **Scaffold chapters and gameplay systems correctly.** When building something new, use the structures defined here.

## How to use this skill

On every EMP Escape turn, before writing code or agreeing to a plan:

1. **Run the off-spec check** (next section). If anything trips, push back *once*, briefly, then wait for the user's call.
2. **Match the request to a system.** If it's a new chapter, follow [Chapter scaffolding](#chapter-scaffolding). If it's combat/inventory/crafting/enemies/movement/camera, follow the relevant section. For the full ruleset, read the project's root `CLAUDE.md`.
3. **Keep code modular and RealityKit-idiomatic.** See [Code conventions](#code-conventions).

---

## Off-spec check (run this first)

Before agreeing to build anything, scan the request for these. If any match, push back **once** with a short explanation citing the rule, then ask whether to proceed anyway. Do not silently refuse, and do not silently comply.

**Hard "no" by default — push back:**

- **Side-scrolling, top-down, isometric, or first-person perspective** — the game is **3rd-person behind-the-shoulder**
- Multiplayer, co-op, PvP, networking, shared worlds
- Currency, trading, markets, loot economy, resource economy
- Pixel art, 8/16-bit graphics, tile-based maps, retro sprites
- Open-world, free-roam, sandbox exploration (chapters are open 3D *spaces*, not an open *world*)
- Random/procedural level generation
- Grinding, level farming, XP loops, resource accumulation
- Crafting trees, weapon upgrade ladders, material farming
- Magic, superpowers, sci-fi weapons, fantasy abilities
- RPG stats, skill trees, classes
- Complex inventory management (weight sim, economic balancing)
- Backtracking loops as a required mechanic

**Push-back format** (keep it short, no lecturing):

> "Heads up — [feature] is off-spec for EMP Escape because [one-line reason from the rules]. The closer-to-spec version would be [alternative]. Want me to do the spec version, or override and build what you asked?"

Then stop and wait. If the user says override / "do it anyway" / equivalent, build what they asked and don't re-litigate.

---

## Core identity (the non-negotiables of the *vision*)

- **Genre:** story-driven survival experience
- **Perspective:** **3rd-person, behind-the-shoulder.** Player-controlled orbit camera: a **right-side look pad (second thumb)** drives camera yaw/pitch; the rig gently auto-recenters behind the heading only while running and not looking. Pitched down from horizontal. No top-down, isometric, first-person, or side-scroller. (Not a tight auto-follow — that caused a movement/camera feedback loop and is avoided.)
- **Movement:** left stick drives the player in **camera-relative XZ** (frame from the camera yaw); the character eases to face its travel direction. Standard 3rd-person controller (camera-relative move + orbit camera) so the body always faces where it moves. Open 3D space the player can navigate *around* obstacles — not corridor-locked, not open-world.
- **Setting:** modern United States, post-EMP collapse, civilian survival, urban → suburban → safe zone progression
- **Tone:** serious, grounded, survival-focused, hopeful
- **Visual style:** modern stylized-realism or clean low-poly, readable mobile silhouettes — *never* pixel art. Primitives are fine for the prototype phase; target USDZ/RealityKit assets for production.
- **Platform:** single-player, mobile-first (iOS via RealityKit), stable 60 FPS, fast load, low memory

The full, authoritative ruleset lives in the project root **`CLAUDE.md`**. Read it when you need detail beyond what's summarized here.

---

## Chapter scaffolding

The game progresses through sequential chapters. When asked to add a new chapter or stub one out, every chapter **must** include all five elements below. If the user's request is missing any, ask for it before writing code.

| Required element | What it means |
|---|---|
| **Start location** | Where the player spawns/enters (a `playerSpawn` in `ChapterConfig`) |
| **Clear objective** | One-sentence goal (e.g. "Reach the server room", "Secure transportation") |
| **Story event** | The narrative beat this chapter delivers (a story-beat interact) |
| **Defined challenge** | At least one major obstacle (environmental, enemy, trap, hazard) |
| **Completion trigger** | The exact condition/volume that ends the chapter and advances the story |

Chapters are data-driven via `ChapterConfig` in `ChapterConfig.swift` (spawn, completion volume, hazard volume, story beat, enemies, workstations, tripwire). Level geometry is built per-chapter in `ThirdPersonSceneController` (e.g. `buildFactoryEnvironment`, `buildTutorialEnvironment`).

Known chapter arc (extend as needed, keep order):

0. Training (tutorial — movement/combat gym)
1. The Event
2. The Neighborhood
3. The City
4. The Escape
5. The Safe Zone

---

## System rules (quick reference)

Full details in the root `CLAUDE.md`. The summaries below are what you need for most code tasks.

### Camera
- Player-orbited rig (`ThirdPersonCameraRig`): yaw/pitch driven by the **right-side look pad**, pitched down, with a gentle auto-recenter behind the heading while running and not looking. Exposes `groundForward` / `groundRight` for camera-relative movement. Do NOT reintroduce tight auto-follow of the heading (it caused a feedback loop / moonwalking).

### Movement
- Camera-relative left-stick input on the XZ plane; player eases to face travel. Velocity-driven physics body with smoothed acceleration and a capped facing-turn rate. Touch input is dead-zoned, curved, and low-passed. The right look pad orbits the camera (two-thumb controls).

### Inventory
- Simple, small fixed slots (8–12), expandable later
- Holds: tools, weapons, medical items, survival supplies, mission items
- **Not** weight-simulated, **not** economically balanced, **not** the focus of gameplay

### Crafting
- Whitelist recipes only, situational and story-driven; gated by story beats and/or workstations
- Valid: traps, equipment repair, basic tools, one-off survival devices
- **Not** a progression system, **not** a tree, **not** material farming

### Combat
- Grounded, physical, tactical, fast
- Hand-to-hand (punch combos, kick, block), improvised weapons (knife, stick), traps (tripwire, spike, ambush). Strikes should give feedback (hit flash, impact burst, haptics, camera kick).
- **No** magic, superpowers, sci-fi weapons, fantasy abilities

### Progression
- Driven by story advancement and chapter completion
- **Not** XP/grinding/resource accumulation

### Controls
- Mobile-first, **two-thumb** touch input, low friction, immediate feedback
- Left stick = camera-relative move; right-side look pad = orbit camera
- Core verbs: Move, Look, Jump, Interact, Attack, Use Item, Trigger Trap

---

## Code conventions

- **Language:** Swift 6, modern concurrency where it fits (`async`/`await`), value types preferred where reasonable
- **UI / HUD / menus:** SwiftUI (MVVM). Observable state in a view model (`GameSessionViewModel`); HUD + RealityView host in `GameRootView`; touch controls in `TraversalTouchOverlay`
- **Engine:** RealityKit 3D. Physics-driven entities for gameplay. `ThirdPersonSceneController` owns the chapter's entities, physics, and game-loop tick
- **Game loop:** drive simulation from a vsync-synced `CADisplayLink`, not a run-loop `Timer` (even frame pacing). Make per-frame math framerate-independent (e.g. `1 - exp(-rate * dt)`)
- **Architecture:** small, modular files — one system / one major entity per file. Avoid god-objects
- **Naming:** clear and game-domain (`ThirdPersonCameraRig`, `ChapterConfig`, `GameSessionViewModel`), not abbreviated jargon
- **Performance posture:** mobile target. Avoid per-frame allocations; pool things that spawn/despawn (debris, impact effects, projectiles); keep meshes/textures within mobile budgets
- **Saves:** simple chapter-based save (current chapter, completion state, inventory snapshot). Do not over-engineer
- **No premature systems:** if the user hasn't asked for it, don't add config files, settings systems, telemetry, or analytics

**When asked to "improve" or "refactor" without a specific target:** prefer simplification. The design philosophy explicitly favors clarity, momentum, tension, and story over complex systems and large feature sets. Less is the right answer more often than not.

---

## What to do when

- **User says "let's add X" and X is off-spec** → push back once per the [Off-spec check](#off-spec-check-run-this-first), then comply if they override
- **User asks for a new chapter** → confirm all five required elements, then scaffold via `ChapterConfig` + a per-chapter environment builder in `ThirdPersonSceneController`
- **User asks for combat/trap/inventory/movement/camera code** → follow the system rules above; read the root `CLAUDE.md` for the full constraint set if the request is non-trivial
- **User pastes code with no context** → assume it's EMP Escape code if it looks like Swift/RealityKit/SwiftUI and matches the game's domain; apply the rules
- **User asks something not covered here** → answer normally, but stay within tone, platform, and complexity constraints

---

## Reference files

- **Project root `CLAUDE.md`** — the authoritative, checked-in design + stack ruleset. Read it for any non-trivial system work.
- **Key source files** — `ThirdPersonCameraRig.swift` (player-orbited camera), `ThirdPersonSceneController.swift` (entities/physics/game-loop tick + level geometry), `GameSessionViewModel.swift` (observable state incl. camera-look deltas + dialog), `GameRootView.swift` (SwiftUI host + HUD), `TraversalTouchOverlay.swift` (move stick + look pad + buttons), `ChapterConfig.swift` (level data incl. NPCs).
