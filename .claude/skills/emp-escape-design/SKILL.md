---
name: emp-escape-design
description: Design rules for EMP Escape, a Telltale-style, chapter-based, dialogue-driven iOS survival game in Unity. Load before any gameplay, story, chapter, scene, or feature work, and to catch off-spec ideas. Supersedes __previous__/.claude/skills/emp-escape (old RealityKit platformer).
---

# EMP Escape design rules

## Identity
- **Genre:** chapter-based, dialogue-driven, choice-and-consequence adventure, modeled on Telltale Games' interaction (not its art).
- **Setting:** modern United States after an EMP/AI attack. Civilian survival. Urban to suburban to safe zone.
- **Tone:** serious, grounded, hopeful. No magic, superpowers, or sci-fi weapons.
- **Platform:** single-player, iOS-first, landscape, touch-only.
- **Art:** Kenney CC0 kits with Mixamo-rigged characters (see art-asset-pipeline). Readable silhouettes, per-chapter color grade. Never pixel art.
- `__previous__/` holds the retired RealityKit platformer. Reference only; its rules (side-scrolling, jumping, combat, inventory) no longer apply.

## Premise
The player is a techno-prepper. When the EMP hits, most tech dies, but their phone survives in a faraday bag
(with a solar panel and a cold crypto wallet). The phone runs a simulated small local AI field guide with preset
questions and answers; more data (packs) is found through the game by photographing manuals and the like.
Phone functions: Field-AI, guide lookup, local Wi-Fi comms, camera, notes, flashlight. See the phone skill.

## Chapter arc (keep order)
1. The Event
2. The Neighborhood
3. The City
4. The Escape
5. The Safe Zone

## Core loop
| Mode | How it plays |
|---|---|
| Explore | Small walkable scenes. Fixed cameras that cut between zones. Drag for a floating virtual stick (free direction, including back toward the camera); tap ground to walk there. Tap hotspots for Look / Use / Talk |
| Talk | Up to 4 choices, often timed. The last choice is silence and is picked on timeout |
| Action | Quick-time events replace real-time combat: tap, mash, hold, **shoot** (drag to aim, lift to fire at set targets, limited rounds) and **swing** (swipe in the arrow's direction; the held knife or bat changes the swipe). A failure is either death-and-retry or a different branch |
| Phone | Opened from the HUD while exploring. Battery is a resource the solar panel refills. Comms chats are Ink conversations shown as messages |
| Weapons | Knife, bat, pistol (more later). Held weapon is story state (Ink `weapon`); it changes which action a scene uses. No stats, durability, or upgrades |
| Choose | 2–3 major choices per chapter set flags. Show "[Name] will remember that." Choice-stats screen at chapter end |

## Decisions
Choices the story marks with `# decision:` are saved across sessions and listed on the CHOICES screen. Later
scenes (and later chapters) read them with Ink `decided("key")`. Telltale-style "what others chose" stats would
need a server: not built.

## Sound
Environment first (wind, birds, distant shots, fire, footsteps, impacts, UI). Character voices come later.

## Action sandbox
`Sandbox.unity` (EMP Escape > Build Action Sandbox) is the test bed for every interaction type, not a level.
New interaction types get a sandbox station first; real levels come later.

## Story structure: branch and bottleneck
Choices change who survives, how characters treat the player, and how scenes play out. Every chapter
reconverges on the same endpoint. Flags carry forward and pay off later, ideally in a different scene.

## Every chapter must define
| Element | Example |
|---|---|
| Start location | Gridlocked off-ramp at dusk |
| Objective (one sentence) | Get off the freeway and see how bad it is |
| Story event | The EMP hits; the player meets Ray |
| Defined challenge | Mash QTE against a stranger at the overpass |
| Major choices (2–3) and the flags they set | Stick with Ray or not → `ray_trust` |
| Completion trigger | Reach the top of the overpass stairs |
If a request for a new chapter is missing any element, ask for it before building.

## Off-spec: push back before building
- Free-roam or open-world maps
- Real-time or stat-based combat, free aiming, health bars, weapon stats (weapons are QTE beats, not a combat system)
- XP, levels, grinding, loot, currency, shops, economy
- Crafting trees or material farming
- Jumping, climbing, or platforming (retired with the old platformer design)
- Multiplayer or online features
- Branches that never reconverge
- Inventory as a core mechanic (a few story items held as Ink flags is fine)

## Cast (generic placeholders)
The owner is still developing characters and plot. Keep characters generic and don't invent names, backstories,
or relationships beyond what exists. Don't build a cast system.
- **Player:** unnamed civilian.
- **Ray:** placeholder survivor met on the off-ramp in Chapter 1. Flag: `ray_trust`. Name and details may change.
- **Stranger:** unnamed attacker at the overpass (voice only, no model yet).
