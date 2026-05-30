import Foundation
import simd

/// Serializable 3D point for chapter JSON-friendly configs.
struct Vector3Config: Codable, Sendable, Hashable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    var simd: SIMD3<Float> { SIMD3(x, y, z) }
}

/// Axis-aligned bounds for spawn and completion volumes (RealityKit world space).
struct AxisAlignedVolumeConfig: Codable, Sendable, Hashable, Equatable {
    var min: Vector3Config
    var max: Vector3Config
}

/// Optional mid-level interactable for a scripted story beat (placeholder props OK).
struct ChapterStoryBeatConfig: Codable, Sendable, Hashable, Equatable {
    /// Stable id for crafting gates and scripting (e.g. `beat.ch2.route_map`).
    var storyBeatId: String
    var worldPosition: Vector3Config
    var interactPrompt: String
    var interactMessage: String
    /// Placed pickup id from `ItemCatalog` (e.g. go-bag). Granted once per chapter run.
    var grantsItemId: String?
    /// When non-empty, overrides single `grantsItemId` for multi-grant beats.
    var grantsItemIds: [String]?
}

extension ChapterStoryBeatConfig {
    /// Resolved grant list: `grantsItemIds` if set, else `[grantsItemId]` when present.
    func resolvedGrantItemIds() -> [String] {
        if let grantsItemIds, !grantsItemIds.isEmpty { return grantsItemIds }
        if let grantsItemId { return [grantsItemId] }
        return []
    }
}

/// In-world crafting surface; recipes reference `id` via `CraftRecipe.requiredWorkstationId`.
struct CraftingWorkstationConfig: Codable, Sendable, Hashable, Equatable {
    var id: String
    var worldPosition: Vector3Config
    var interactPrompt: String
}

/// Hostile patrol dummy; grounded melee only (no sci-fi weapons).
struct CombatEnemyConfig: Codable, Sendable, Hashable, Equatable {
    var id: String
    var worldPosition: Vector3Config
    /// Patrol between `worldPosition.x ± patrolHalfWidth`.
    var patrolHalfWidth: Float
    var moveSpeed: Float
    var maxHealth: Float
}

/// Tripwire: interact at anchor to consume kit and arm; first enemy in trigger volume takes damage.
struct TripwireTrapConfig: Codable, Sendable, Hashable, Equatable {
    var armAnchorPosition: Vector3Config
    var interactPrompt: String
    var triggerVolume: AxisAlignedVolumeConfig
}

/// One branching dialog option. Choices are remembered (`DialogChoiceConfig.id`)
/// for later narrative consequences; `turnsHostile` makes an NPC attack after picking it.
struct DialogChoiceConfig: Codable, Sendable, Hashable, Equatable {
    var id: String
    var label: String
    /// NPC's reply shown after the choice is picked.
    var response: String
    /// Enemy-dialog only: choosing this converts the NPC into a hostile.
    var turnsHostile: Bool
}

/// An interactable character. Friendlies cannot be attacked and always offer dialog;
/// enemies may offer dialog (a choice can turn them hostile) or be hostile-only.
struct NPCConfig: Codable, Sendable, Hashable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var isFriendly: Bool
    var worldPosition: Vector3Config
    var interactPrompt: String
    var openingLine: String
    var choices: [DialogChoiceConfig]
    /// Combat stats applied if a `turnsHostile` choice is picked.
    var combatMaxHealth: Float?
    var combatMoveSpeed: Float?
    var patrolHalfWidth: Float?
}

/// Hand-authored chapter metadata: objective id, spawn, completion trigger id, narrative text ids.
struct ChapterConfig: Codable, Sendable, Identifiable, Hashable, Equatable {
    /// Stable id for saves and routing (e.g. `chapter.event`).
    var id: String
    /// Sequential order; used for unlock progression.
    var orderIndex: Int
    /// Short player-facing title.
    var title: String
    /// Machine objective id (analytics / scripting).
    var objectiveId: String
    /// Localization key or catalog id for intro copy.
    var narrativeIntroTextId: String
    /// Matches in-world completion entity / volume id.
    var completionTriggerId: String
    var playerSpawn: Vector3Config
    var completionVolume: AxisAlignedVolumeConfig

    /// One-line HUD hint; can mirror `objectiveId` until copy exists.
    var objectiveHUDLine: String

    /// Grounded hazard volume (e.g. live bus bar). Nil when this chapter has no hazard strip.
    var hazardVolume: AxisAlignedVolumeConfig?
    /// Designer-placed story beat after major traversal; nil if unused.
    var storyBeat: ChapterStoryBeatConfig?
    /// Optional workbenches for whitelist crafting (chapter 2+).
    var craftingWorkstations: [CraftingWorkstationConfig]?
    /// Optional hostile patrols for melee / tripwire demo.
    var combatEnemies: [CombatEnemyConfig]?
    /// Optional tripwire: anchor interact + trigger volume.
    var tripwire: TripwireTrapConfig?
    /// Optional interactable characters (friendlies + dialog enemies).
    var npcs: [NPCConfig]? = nil
}

// MARK: - Level layout  ─  Futuristic Neo-Tokyo Drone Factory
//
// World orientation: player spawns at origin facing -Z.
// Camera sits at +Z behind the player, looking into the factory.
//
// Route overview:
//   LEFT (X ≈ -13 to -5):  Safe, blue-neon path behind large machinery
//   CENTER (X ≈ -4 to 4):  Risky, red-neon drone patrol zone
//   RIGHT (X ≈  5 to 13):  Alt path with some cover, no neon safety markers
//   Z=-30 chokepoint:       All three routes merge at the security gate
//   Z=-36 to -50:           Server room corridor → exit

enum ChapterRegistry {
    static let chapters: [ChapterConfig] = [
        // ── Tutorial — Training Yard ──────────────────────────────────────────
        // Calm, flat course that teaches fluid movement: open plaza, slalom,
        // speed lane, jump the live-wire hazard, grab a supply cache, reach exit.
        ChapterConfig(
            id: "chapter.tutorial",
            orderIndex: 0,
            title: "Training",
            objectiveId: "tutorial_movement",
            narrativeIntroTextId: "narrative.tutorial.intro",
            completionTriggerId: "trigger.tutorial_exit",
            playerSpawn: Vector3Config(x: 0, y: 0.55, z: 0),
            completionVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -4, y: 0, z: -50),
                max: Vector3Config(x:  4, y: 5, z: -46)
            ),
            objectiveHUDLine: "Weave the dummies, clear the hurdle, grab supplies, reach the exit",
            hazardVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -3.5, y: 0, z: -35.2),
                max: Vector3Config(x:  3.5, y: 1.0, z: -33.8)
            ),
            storyBeat: ChapterStoryBeatConfig(
                storyBeatId: "beat.tutorial.supplies",
                worldPosition: Vector3Config(x: 0, y: 0.5, z: -41),
                interactPrompt: "Grab supplies",
                interactMessage: "Supply cache secured — weapons and gear inside. Open your bag to equip them.",
                grantsItemId: nil,
                grantsItemIds: [
                    "item.go_bag",
                    "item.knife",
                    "item.baton",
                    "item.pistol",
                    "item.work_shirt",
                    "item.cargo_pants",
                    "item.work_gloves",
                    "item.balaclava",
                ]
            ),
            craftingWorkstations: nil,
            // No-dialog hostile: a sparring bot you can simply attack.
            combatEnemies: [
                CombatEnemyConfig(
                    id: "hostile.sparring_bot",
                    worldPosition: Vector3Config(x: 4, y: 0.55, z: -29),
                    patrolHalfWidth: 2.5,
                    moveSpeed: 1.1,
                    maxHealth: 1.0
                ),
            ],
            tripwire: nil,
            npcs: [
                // Friendly trainer — always dialog, never attackable.
                NPCConfig(
                    id: "npc.trainer_maya",
                    displayName: "Maya",
                    isFriendly: true,
                    worldPosition: Vector3Config(x: 3.5, y: 0, z: -5),
                    interactPrompt: "Talk to Maya",
                    openingLine: "New here? Follow the green line. Want the quick rundown?",
                    choices: [
                        DialogChoiceConfig(id: "yes", label: "Yes",
                            response: "Weave the dummies, clear the hurdle, grab supplies, hit the exit. Go.",
                            turnsHostile: false),
                        DialogChoiceConfig(id: "no", label: "No",
                            response: "Suit yourself. Yell if you need me.",
                            turnsHostile: false),
                    ],
                    combatMaxHealth: nil, combatMoveSpeed: nil, patrolHalfWidth: nil
                ),
                // Dialog enemy — a choice can turn this one hostile.
                NPCConfig(
                    id: "npc.drifter",
                    displayName: "Drifter",
                    isFriendly: false,
                    worldPosition: Vector3Config(x: -3.5, y: 0, z: -27),
                    interactPrompt: "Confront the drifter",
                    openingLine: "That pack yours? Hand it over and we're fine.",
                    choices: [
                        DialogChoiceConfig(id: "back_off", label: "Back off",
                            response: "Wrong answer.",
                            turnsHostile: true),
                        DialogChoiceConfig(id: "stay_calm", label: "Stay calm",
                            response: "...Smart. Get moving.",
                            turnsHostile: false),
                    ],
                    combatMaxHealth: 1.0, combatMoveSpeed: 1.2, patrolHalfWidth: 2.0
                ),
            ]
        ),
        // ── Chapter 1 — The Event (factory intro) ─────────────────────────────
        // Objective: reach the server room exit at Z ≈ -50.
        // Hazard: drone patrol zone in the center lane (Z=-9 to -29, X=-4 to 4).
        // Story beat: hack terminal at security gate (Z≈-34.5).
        // Enemy: one guard patrolling the server corridor.
        ChapterConfig(
            id: "chapter.event",
            orderIndex: 1,
            title: "The Event",
            objectiveId: "reach_server_room",
            narrativeIntroTextId: "narrative.ch1.intro",
            completionTriggerId: "trigger.server_exit",
            playerSpawn: Vector3Config(x: 0, y: 0.55, z: 0),
            completionVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -5,  y: 0, z: -50),
                max: Vector3Config(x:  5,  y: 5, z: -46)
            ),
            objectiveHUDLine: "Reach the server room",
            hazardVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -4,  y: 0, z: -29),
                max: Vector3Config(x:  4,  y: 3, z:  -9)
            ),
            storyBeat: ChapterStoryBeatConfig(
                storyBeatId: StoryBeatIds.ch1GoBag,
                worldPosition: Vector3Config(x: -7, y: 0.5, z: -34.5),
                interactPrompt: "Hack terminal",
                interactMessage: "Access granted. Server room unlocked — move before the drones recalibrate.",
                grantsItemId: "item.go_bag",
                grantsItemIds: nil
            ),
            craftingWorkstations: nil,
            combatEnemies: [
                CombatEnemyConfig(
                    id: "hostile.corridor_guard",
                    worldPosition: Vector3Config(x: 0, y: 0.55, z: -41),
                    patrolHalfWidth: 4.0,
                    moveSpeed: 1.1,
                    maxHealth: 1.0
                ),
            ],
            tripwire: nil
        ),
        // ── Chapter 2 — The Neighborhood ──────────────────────────────────────
        // Reuses the same factory geometry; workbench and tripwire added.
        ChapterConfig(
            id: "chapter.neighborhood",
            orderIndex: 2,
            title: "The Neighborhood",
            objectiveId: "escape_to_arterial",
            narrativeIntroTextId: "narrative.ch2.intro",
            completionTriggerId: "trigger.neighborhood_gate",
            playerSpawn: Vector3Config(x: 0, y: 0.55, z: 0),
            completionVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -5,  y: 0, z: -50),
                max: Vector3Config(x:  5,  y: 5, z: -46)
            ),
            objectiveHUDLine: "Reach the arterial exit",
            hazardVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: -4,  y: 0, z: -29),
                max: Vector3Config(x:  4,  y: 3, z:  -9)
            ),
            storyBeat: ChapterStoryBeatConfig(
                storyBeatId: StoryBeatIds.ch2RouteMap,
                worldPosition: Vector3Config(x: -7, y: 0.5, z: -34.5),
                interactPrompt: "Read route data",
                interactMessage: "Arterial route confirmed. Grab what you need from the workbench.",
                grantsItemId: nil,
                grantsItemIds: [
                    "item.route_map",
                    "item.scrap_wire",
                    "item.scrap_wire",
                    "item.stick",
                ]
            ),
            craftingWorkstations: [
                CraftingWorkstationConfig(
                    id: "workbench.neighborhood",
                    worldPosition: Vector3Config(x: 7, y: 0.5, z: -34.5),
                    interactPrompt: "Use workbench"
                ),
            ],
            combatEnemies: [
                CombatEnemyConfig(
                    id: "hostile.scavenger_a",
                    worldPosition: Vector3Config(x: 0, y: 0.55, z: -22),
                    patrolHalfWidth: 3.5,
                    moveSpeed: 1.2,
                    maxHealth: 1.0
                ),
            ],
            tripwire: TripwireTrapConfig(
                armAnchorPosition: Vector3Config(x: -4, y: 0.55, z: -29),
                interactPrompt: "Rig tripwire at gate post",
                triggerVolume: AxisAlignedVolumeConfig(
                    min: Vector3Config(x: -2, y: 0, z: -23),
                    max: Vector3Config(x:  2, y: 2, z: -21)
                )
            )
        ),
    ]

    static func chapter(id: String) -> ChapterConfig? {
        chapters.first { $0.id == id }
    }
}
