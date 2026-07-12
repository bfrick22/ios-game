# EMP Escape — Project Rules & Stack

## Stack

- **Language:** Swift 6.x
- **UI / menus / HUD:** SwiftUI
- **Game scenes:** RealityKit (3D)
- **Audio:** AVFoundation (procedural via `AVAudioEngine` — no asset files yet)
- **Async state:** Swift Concurrency (`async`/`await`)
- **Architecture:** MVVM for UI; physics-driven entities for gameplay

## Key files

| File | Role |
|---|---|
| `ThirdPersonCameraRig.swift` | Player-orbited camera: yaw/pitch driven by the look pad, gentle auto-recenter behind heading; exposes `groundForward`/`groundRight` for camera-relative movement |
| `ThirdPersonSceneController.swift` | Owns all RealityKit entities, physics, game loop tick |
| `GameSessionViewModel.swift` | Observable state: input, camera-look deltas, health, inventory, prompts, dialog |
| `GameRootView.swift` | SwiftUI host: RealityView + HUD + `CADisplayLink` loop |
| `TraversalTouchOverlay.swift` | Left move stick + right-side camera look pad + action buttons |
| `ChapterConfig.swift` | Level data: spawn, volumes, enemies, beats, NPCs |

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
- **Camera:** player-controlled orbit. The **right-side look pad (second thumb)** is the only thing that turns the camera (yaw + pitch). Pitched down from horizontal. **No auto-follow / auto-recenter** — the camera stays where the player puts it. (Auto-follow was tried and caused a feedback loop / moonwalking; intentionally removed.)
- **Movement (camera-aligned):** left stick drives the player in **camera-relative XZ** (frame from the camera yaw, `groundForward`/`groundRight`); the body **aligns to the camera's forward** — stick input *never* rotates the body. Only the look pad turns the body. Up = walk forward into the screen, down = backpedal (body keeps facing forward, no spin), left/right = strafe. This is the camera-aligned variant of 3rd-person controls; it reliably eliminates the moonwalk/spin failure modes of a "face the travel direction" model.

### 4 — Visual style

- **No pixel art.** Modern stylized-realism or clean low-poly; mobile-readable silhouettes.
- **Primitives OK** for prototype phase; target USDZ/RealityKit assets for production.
- **Tone:** modern, grounded, immersive.

### 5 — Story design

- **Narrative-first.** Gameplay systems exist to serve the story.
- **Per chapter:** clear objective, story event (interact beat), defined challenge, resolution.

### 6 — Inventory

- Small fixed-slot inventory (10 slots). Categories: tool, weapon, medical, supply, mission, **apparel**.
- Inventory + equipped items **persist across chapters**; per-chapter state (story beats, dialog, prompts) resets on chapter entry.
- **No** weight simulation, complex sorting, or deep management UI.

### 7 — Crafting

- **Whitelist recipes only** (~3–8 for a vertical slice). Gated by story beats and/or workstations.
- **No** crafting trees, material farming, or discovery loops.

### 8 — Combat

- **Melee:** grounded combo (jab → cross → kick), improvised weapons (knife, baton, stick, reinforced stick). Held weapon is visible in the right hand. Strikes give feedback (white flash on hit, spark burst, haptics, camera kick, audio thud).
- **Ranged:** grounded firearms (e.g. pistol). Hitscan from the camera's forward; **damage is constant across the full range — no falloff** (real-firearm round). Finite magazine; **no reload system yet** — running dry is the limit. Aim reticle shows when a ranged weapon is equipped; HUD shows ammo count.
- **Traps:** tripwire, etc. Designer-placed, story-gated.
- **No** magic, superpowers, sci-fi weapons. Post-EMP, grounded toolkit only.

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

- Touch-first, **two-thumb**: virtual **left stick** (camera-relative movement) + **right-side look pad** (drag to orbit the camera), plus jump, interact, attack buttons.
- **Left stick:** forward/back/strafe relative to camera facing; character faces travel direction.
- **Right look pad:** drag to rotate camera yaw/pitch (the only way to turn the camera — no auto-snap).
- Large targets, HIG-friendly, immediate feedback.

### 14 — Performance

- Target smooth 60 FPS on device. One chapter scene active at a time; unload on teardown.
- Minimize per-tick allocations. Pool frequently spawned objects.

### 15 — Tone and setting

- Modern United States, post-EMP collapse. Civilian survival, urban-to-safe-zone journey.
- Serious, grounded, hopeful.

---

## System notes — what's actually built

Beyond the core rules above, these systems are implemented and any new work should compose with them (not reinvent or contradict).

- **Audio (`AudioEngine` in `GameRootView.swift`)** — procedural via `AVAudioEngine`; no asset files needed. Cues: `strikeHit`, `strikeWhiff`, `jump`, `land`, `hazard`, `dialogOpen`, `dialogClose`, `pickup`, `equip`, `gunshot`, `dryFire`. Drop in real `.wav`s later by swapping the recipe functions for buffer loaders.
- **Strike feedback** — every connected strike triggers a spark burst, white target flash, haptic, camera shake, and audio thud. Training-gym dummies are non-damage strikable targets that swing on a damped spring; enemies take damage + flash.
- **Gear / armor** — apparel (shirt/pants/gloves/mask) equipped via the Bag's **Use** action; recolors the rig parts (`shirtParts` / `pantsParts` / `handParts`) or mounts a mask mesh on `HeadGearMount`. Each piece grants damage resistance that stacks (capped at 80%); HUD shows armor %.
- **Held-weapon visuals** — equipped weapon (knife / baton / stick / pistol / etc.) is shown as a procedural mesh in the player's right hand. Swap is diffed via `applyHeldWeaponIfChanged`.
- **NPCs / dialog** — data-driven via `NPCConfig`. Friendly NPCs always have dialog and **cannot be attacked**; enemy NPCs may have dialog where a `turnsHostile` choice converts them into a patrolling combat enemy (re-using the NPC's figure). Choices recorded into `npcChoices`. **Telltale-style consequence layer is planned** (recorded → propagated to later content); not yet wired — design it before retro-fitting many NPCs.
- **Interactable indicators** — floating color-coded orbs above NPCs and pickups (green friendly, amber dialog-enemy, gold supply). Pulse at idle, scale up when the player is within interact reach. Interact button icon also pulses via `.symbolEffect(.pulse)` when actionable. Supply orb auto-hides once the cache has been looted.
- **Chapter progression** — `ChapterSelectView` uses conditional rendering on a `currentChapter` state with `.id(chapter.id)` to re-create `GameRootView` cleanly per chapter. Reaching the completion volume shows a **Chapter Complete** overlay with **Continue → [Next Chapter]** and **Back to Chapters**. Do NOT use `NavigationStack` path mutation for game→game transitions — it was tried and failed silently.
- **Save / persistence** — chapter-level only: `ChapterProgressViewModel` tracks `highestUnlockedChapterIndex`, persisted via `GameProgressStore`. Mid-chapter checkpoints (respawn on death, save anywhere) are NOT implemented.

---

## Implementation checklist

Before adding a feature, confirm:
- 3rd-person camera + chapter story beat + no prohibited genres + simple expandable code + mobile performance.
