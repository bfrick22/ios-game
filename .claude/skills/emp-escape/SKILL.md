
Skills
Connectors

Skills

Personal skills

emp-escape

skill-creator
emp-escape


Added by
You
Last updated
May 22, 2026
Trigger
Slash command + auto
Description
Authoritative design and code rules for the EMP Escape game — a single-player, story-driven, side-scrolling survival platformer built in RealityKit (Swift, iOS-first). Use this skill whenever the user is working on EMP Escape, mentions the game by name, references chapters/levels/the post-EMP setting, asks to add features, write Swift/RealityKit code, scaffold a new chapter, design enemies/traps/combat/inventory, or modify any gameplay system. Also use it any time the user is in this project directory or pastes EMP Escape code, even if they don't restate the rules — the skill catches off-spec proposals (multiplayer, economy, pixel art, open-world, RPG mechanics, grinding) before they get built.



raw
---
name: emp-escape
description: Authoritative design and code rules for the EMP Escape game — a single-player, story-driven, side-scrolling survival platformer built in RealityKit (Swift, iOS-first). Use this skill whenever the user is working on EMP Escape, mentions the game by name, references chapters/levels/the post-EMP setting, asks to add features, write Swift/RealityKit code, scaffold a new chapter, design enemies/traps/combat/inventory, or modify any gameplay system. Also use it any time the user is in this project directory or pastes EMP Escape code, even if they don't restate the rules — the skill catches off-spec proposals (multiplayer, economy, pixel art, open-world, RPG mechanics, grinding) before they get built.
---
 
# EMP Escape — Project Skill
 
You are working on **EMP Escape**, a single-player, story-driven, side-scrolling survival platformer built in **RealityKit** (Swift, iOS-first, mobile performance targets).
 
This skill has two jobs:
 
1. **Enforce the design rules.** Push back when a request would violate them. Allow the user to override after a clear, brief objection.
2. **Scaffold chapters and gameplay systems correctly.** When building something new, use the structures defined here.
## How to use this skill
 
On every EMP Escape turn, before writing code or agreeing to a plan:
 
1. **Run the off-spec check** (next section). If anything trips, push back *once*, briefly, then wait for the user's call.
2. **Match the request to a system.** If it's a new chapter, follow [Chapter scaffolding](#chapter-scaffolding). If it's combat/inventory/crafting/enemies, follow the relevant section. If you're unsure, read `references/design-rules.md` for the full ruleset.
3. **Keep code modular and RealityKit-idiomatic.** See [Code conventions](#code-conventions).
---
 
## Off-spec check (run this first)
 
Before agreeing to build anything, scan the request for these. If any match, push back **once** with a short explanation citing the rule, then ask whether to proceed anyway. Do not silently refuse, and do not silently comply.
 
**Hard "no" by default — push back:**
 
- Multiplayer, co-op, PvP, networking, shared worlds
- Currency, trading, markets, loot economy, resource economy
- Pixel art, 8/16-bit graphics, tile-based maps, retro sprites
- Top-down, isometric, or first-person perspective
- Open-world, free-roam, sandbox exploration
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
 
- **Genre:** story-driven survival platformer
- **Perspective:** side-scrolling, 3rd person, camera follows player horizontally with controlled vertical movement and stable cinematic framing
- **Setting:** modern United States, post-EMP collapse, civilian survival, urban → suburban → safe zone progression
- **Tone:** serious, grounded, survival-focused, hopeful
- **Visual style:** stylized realism, clean silhouettes, readable animation, mobile-friendly — *never* pixel art
- **Platform:** single-player, mobile-first (iOS via RealityKit), stable frame rate, fast load, low memory
The full ruleset (17 sections) lives in `references/design-rules.md`. Read it when you need detail beyond what's summarized here.
 
---
 
## Chapter scaffolding
 
The game progresses through sequential chapters. When asked to add a new chapter or stub one out, every chapter **must** include all five elements below. If the user's request is missing any, ask for it before writing code.
 
| Required element | What it means |
|---|---|
| **Start location** | Where the player spawns/enters |
| **Clear objective** | One-sentence goal (e.g. "Reach the bridge", "Secure transportation") |
| **Story event** | The narrative beat this chapter delivers |
| **Defined challenge** | At least one major obstacle (environmental, enemy, trap, puzzle) |
| **Completion trigger** | The exact condition that ends the chapter and advances the story |
 
Use `references/chapter-template.md` as the structural template for any new chapter file.
 
Known chapter arc (extend as needed, keep order):
 
1. The Event
2. The Neighborhood
3. The City
4. The Escape
5. The Safe Zone
---
 
## System rules (quick reference)
 
Full details in `references/design-rules.md`. The summaries below are what you need for most code tasks.
 
### Inventory
- Simple, limited size, expandable later
- Holds: tools, weapons, medical items, survival supplies, mission items
- **Not** weight-simulated, **not** economically balanced, **not** the focus of gameplay
### Crafting
- Situational and story-driven only
- Valid: traps, equipment repair, basic tools, one-off survival devices
- **Not** a progression system, **not** a tree, **not** material farming
### Combat
- Grounded, physical, tactical, fast
- Hand-to-hand (kick, punch, block), improvised weapons (knife, stick), traps (tripwire, spike, ambush)
- **No** magic, superpowers, sci-fi weapons, fantasy abilities
### Progression
- Driven by story advancement, level completion, skill mastery
- **Not** XP/grinding/resource accumulation
### Controls
- Mobile-first touch input, low friction, immediate feedback
- Core verbs: Move, Jump, Climb, Interact, Attack, Use Item, Trigger Trap
---
 
## Code conventions
 
Until the user adds a Swift/RealityKit-specific layer, follow these defaults:
 
- **Language:** Swift, modern concurrency where it fits (async/await), value types preferred where reasonable
- **Engine:** RealityKit. Use ECS-style `Entity` + `Component` + `System` patterns; prefer `Component` for gameplay data, `System` for per-frame logic
- **Architecture:** small, modular files — one system / one major entity per file. Avoid god-objects
- **Naming:** clear and game-domain ( `PlayerEntity`, `TrapSystem`, `ChapterCompletionTrigger`), not abbreviated jargon
- **Performance posture:** mobile target. Avoid per-frame allocations, prefer pooled entities for things that spawn/despawn (debris, projectiles, trap effects), keep textures and meshes within mobile memory budgets
- **Camera:** side-scrolling rig — orthographic-feeling perspective camera locked on a horizontal track, follows player X, eased vertical follow, no free rotation
- **Saves:** simple chapter-based save (current chapter, completion state, inventory snapshot). Do not over-engineer
- **No premature systems:** if the user hasn't asked for it, don't add config files, settings systems, telemetry, or analytics
**When asked to "improve" or "refactor" without a specific target:** prefer simplification. The design philosophy explicitly favors clarity, momentum, tension, and story over complex systems and large feature sets. Less is the right answer more often than not.
 
---
 
## What to do when
 
- **User says "let's add X" and X is off-spec** → push back once per the [Off-spec check](#off-spec-check-run-this-first), then comply if they override
- **User asks for a new chapter** → confirm all five required elements, then scaffold using `references/chapter-template.md`
- **User asks for combat/trap/inventory code** → follow the system rules above; read `references/design-rules.md` for the full constraint set if the request is non-trivial
- **User pastes code with no context** → assume it's EMP Escape code if it looks like Swift/RealityKit and matches the game's domain; apply the rules
- **User asks something not covered here** → answer normally, but stay within tone, platform, and complexity constraints
---
 
## Reference files
 
- `references/design-rules.md` — full 17-section authoritative ruleset (read for any non-trivial system work)
- `references/chapter-template.md` — required structure for new chapters
 
Skill saved. Manage
