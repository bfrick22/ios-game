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
}

enum ChapterRegistry {
    static let chapters: [ChapterConfig] = [
        ChapterConfig(
            id: "chapter.event",
            orderIndex: 0,
            title: "The Event",
            objectiveId: "reach_safe_exit",
            narrativeIntroTextId: "narrative.ch1.intro",
            completionTriggerId: "trigger.home_exit",
            playerSpawn: Vector3Config(x: 0, y: 0.72, z: 0),
            completionVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: 10.75, y: 0.02, z: -1.1),
                max: Vector3Config(x: 12.6, y: 4.0, z: 1.1)
            ),
            objectiveHUDLine: "Reach the exit corridor",
            hazardVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: 5.5, y: 0.28, z: -0.95),
                max: Vector3Config(x: 7.05, y: 1.12, z: 0.95)
            ),
            storyBeat: ChapterStoryBeatConfig(
                storyBeatId: StoryBeatIds.ch1GoBag,
                worldPosition: Vector3Config(x: 8.15, y: 0.55, z: 0),
                interactPrompt: "Grab go-bag",
                interactMessage: "You shoulder the bag. Whatever hit the grid, it is not coming back tonight.",
                grantsItemId: "item.go_bag",
                grantsItemIds: nil
            ),
            craftingWorkstations: nil,
            combatEnemies: nil,
            tripwire: nil
        ),
        ChapterConfig(
            id: "chapter.neighborhood",
            orderIndex: 1,
            title: "The Neighborhood",
            objectiveId: "escape_to_arterial",
            narrativeIntroTextId: "narrative.ch2.intro",
            completionTriggerId: "trigger.neighborhood_gate",
            playerSpawn: Vector3Config(x: 5.5, y: 0.72, z: 0),
            completionVolume: AxisAlignedVolumeConfig(
                min: Vector3Config(x: 10.75, y: 0.02, z: -1.1),
                max: Vector3Config(x: 12.6, y: 4.0, z: 1.1)
            ),
            objectiveHUDLine: "Reach the arterial exit",
            hazardVolume: nil,
            storyBeat: ChapterStoryBeatConfig(
                storyBeatId: StoryBeatIds.ch2RouteMap,
                worldPosition: Vector3Config(x: 8.15, y: 0.55, z: 0),
                interactPrompt: "Read route marker",
                interactMessage: "Chalk arrow points toward the arterial — still no power, still no radios.",
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
                    worldPosition: Vector3Config(x: 6.2, y: 0.55, z: 0),
                    interactPrompt: "Use workbench"
                ),
            ],
            combatEnemies: [
                CombatEnemyConfig(
                    id: "hostile.scavenger_a",
                    worldPosition: Vector3Config(x: 7.5, y: 0.55, z: 0),
                    patrolHalfWidth: 0.95,
                    moveSpeed: 1.15,
                    maxHealth: 1.0
                ),
            ],
            tripwire: TripwireTrapConfig(
                armAnchorPosition: Vector3Config(x: 5.95, y: 0.55, z: 0),
                interactPrompt: "Rig tripwire",
                triggerVolume: AxisAlignedVolumeConfig(
                    min: Vector3Config(x: 6.88, y: 0.05, z: -0.55),
                    max: Vector3Config(x: 7.28, y: 1.55, z: 0.55)
                )
            )
        ),
    ]

    static func chapter(id: String) -> ChapterConfig? {
        chapters.first { $0.id == id }
    }
}
