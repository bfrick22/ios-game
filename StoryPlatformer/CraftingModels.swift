import Foundation

/// Single ingredient line for a whitelist recipe (no procedural trees).
struct CraftIngredient: Sendable, Hashable, Equatable {
    var itemId: String
    var quantity: Int
}

/// Fixed designer recipe: optional story-beat and workstation gates only.
struct CraftRecipe: Sendable, Hashable, Equatable {
    var id: String
    var displayName: String
    var ingredients: [CraftIngredient]
    var outputItemId: String
    var outputQuantity: Int
    /// When non-nil, player must have completed this story beat this run (see `GameSessionViewModel`).
    var requiredStoryBeatId: String?
    /// When non-nil, player must be in range of this workstation id (from `ChapterConfig`).
    var requiredWorkstationId: String?
}

/// Small static whitelist only — no farming loops or discovery trees.
enum RecipeCatalog {
    static let all: [CraftRecipe] = [
        CraftRecipe(
            id: "recipe.tripwire_kit",
            displayName: "Tripwire kit",
            ingredients: [
                CraftIngredient(itemId: "item.scrap_wire", quantity: 2),
                CraftIngredient(itemId: "item.stick", quantity: 1),
            ],
            outputItemId: "item.tripwire_kit",
            outputQuantity: 1,
            requiredStoryBeatId: StoryBeatIds.ch2RouteMap,
            requiredWorkstationId: "workbench.neighborhood"
        ),
        CraftRecipe(
            id: "recipe.reinforced_stick",
            displayName: "Reinforced stick",
            ingredients: [
                CraftIngredient(itemId: "item.scrap_wire", quantity: 1),
                CraftIngredient(itemId: "item.stick", quantity: 1),
            ],
            outputItemId: "item.reinforced_stick",
            outputQuantity: 1,
            requiredStoryBeatId: StoryBeatIds.ch2RouteMap,
            requiredWorkstationId: "workbench.neighborhood"
        ),
    ]

    static func recipe(id: String) -> CraftRecipe? {
        all.first { $0.id == id }
    }
}

enum StoryBeatIds {
    static let ch1GoBag = "beat.ch1.go_bag"
    static let ch2RouteMap = "beat.ch2.route_map"
}
