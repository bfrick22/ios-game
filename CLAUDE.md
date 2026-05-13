# EMP Escape — Project Rules & Stack

## Stack

- **Language:** Swift 6.x
- **UI / menus / HUD:** SwiftUI
- **Game scenes:** RealityKit (3D)
- **Async state:** Swift Concurrency (`async`/`await`)
- **Architecture:** MVVM for UI; physics-driven entities for gameplay

## Key files

| File | Role |
|---|---|
| `ThirdPersonCameraRig.swift` | Orbit camera: follows behind player, exposes `groundForward`/`groundRight` for movement |
| `ThirdPersonSceneController.swift` | Owns all RealityKit entities, physics, game loop tick |
| `GameSessionViewModel.swift` | Observable state: input, health, inventory, prompts |
| `GameRootView.swift` | SwiftUI host: RealityView + HUD + timer |
| `TraversalTouchOverlay.swift` | Virtual stick + action buttons |
| `ChapterConfig.swift` | Level data: spawn, volumes, enemies, beats |

---

## Game design rules

### 1 — Core identity

**The game is:** a story-driven survival experience.

**Not:** open-world sandbox, survival simulator, MMO, or RPG economy.

**Primary focus:** 3rd-person movement, survival tension, narrative progression, environmental challenges.

### 2 — Game structure

- **Chapter-based progression only.** Sequential phases of the survival journey (The Event → Neighborhood → City → Escape → Safe Zone).
- **Each chapter must have:** a clear objective, a completion trigger, and story advancement.
- **Never rely on:** random generation, grinding, or sandbox exploration as core loop.

### 3 — Gameplay perspective

- **3rd-person only:** behind-the-shoulder camera (Uncharted / Alan Wake style).
- **Not allowed:** top-down, isometric, first-person, side-scroller, or free-roam open world.
- **Camera:** auto-follows player heading; smooth yaw lag; pitched down from horizontal; always behind player.
- **Movement:** left-stick drives player in camera-relative XZ; player character rotates to face movement direction.

### 4 — Visual style

- **No pixel art.** Modern stylized-realism or clean low-poly; mobile-readable silhouettes.
- **Primitives OK** for prototype phase; target USDZ/RealityKit assets for production.
- **Tone:** modern, grounded, immersive.

### 5 — Story design

- **Narrative-first.** Gameplay systems exist to serve the story.
- **Per chapter:** clear objective, story event (interact beat), defined challenge, resolution.

### 6 — Inventory

- Small fixed-slot inventory (8–10 slots). Categories: tool, weapon, medical, supply, mission.
- **No** weight simulation, complex sorting, or deep management UI.

### 7 — Crafting

- **Whitelist recipes only** (~3–8 for a vertical slice). Gated by story beats and/or workstations.
- **No** crafting trees, material farming, or discovery loops.

### 8 — Combat

- Grounded melee + improvised weapons + traps. Physical, fast, tactical.
- **No** magic, superpowers, or sci-fi weapons. Post-EMP, grounded toolkit only.

### 9 — Multiplayer

- **Single-player only.**

### 10 — Economy

- **No** currency, trading, shops, loot tables, or rarity. Designer-placed pickups only.

### 11 — Progression

- Via story advancement and chapter completion. **No** XP grinding or procedural maps.

### 12 — Level design

- Each level: spawn, objective, environmental obstacles, at least one major challenge, completion trigger.
- **Open 3D space** (not corridor-locked); player can navigate around obstacles.
- **Avoid** mandatory long backtracking.

### 13 — Controls

- Touch-first: virtual left stick (camera-relative movement), jump, interact, attack.
- **Left stick:** forward/back/strafe relative to camera facing.
- Large targets, HIG-friendly, immediate feedback.

### 14 — Performance

- Target smooth 60 FPS on device. One chapter scene active at a time; unload on teardown.
- Minimize per-tick allocations. Pool frequently spawned objects.

### 15 — Tone and setting

- Modern United States, post-EMP collapse. Civilian survival, urban-to-safe-zone journey.
- Serious, grounded, hopeful.

---

## Implementation checklist

Before adding a feature, confirm:
- 3rd-person camera + chapter story beat + no prohibited genres + simple expandable code + mobile performance.
