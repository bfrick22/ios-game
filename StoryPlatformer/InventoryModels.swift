import Foundation

enum ItemCategory: String, Codable, Sendable, Hashable {
    case tool
    case weapon
    case medical
    case supply
    case mission
}

/// Designer-facing item metadata; resolve `use` / equip / consume in `GameSessionViewModel`.
struct ItemDefinition: Sendable, Hashable, Equatable {
    var id: String
    var displayName: String
    var category: ItemCategory
    /// Max units per inventory slot; mission / weapons / tools stay at 1.
    var maxStack: Int
    var systemImageName: String
    /// Medical only: fraction of max health restored per consume (0…1).
    var healFraction: Float?
    /// Mission item: shown when player taps Use (no consume).
    var missionUseMessage: String?
}

struct InventoryStack: Sendable, Hashable, Equatable {
    var itemId: String
    var quantity: Int
}

enum ItemCatalog {
    static let slotCount = 10

    static func definition(for itemId: String) -> ItemDefinition? {
        all[itemId]
    }

    private static let all: [String: ItemDefinition] = [
        "item.go_bag": ItemDefinition(
            id: "item.go_bag",
            displayName: "Go-bag",
            category: .mission,
            maxStack: 1,
            systemImageName: "backpack.fill",
            healFraction: nil,
            missionUseMessage: "Your go-bag is packed for a hard exit — keep it close until you are clear."
        ),
        "item.route_map": ItemDefinition(
            id: "item.route_map",
            displayName: "Marked map",
            category: .mission,
            maxStack: 1,
            systemImageName: "map.fill",
            healFraction: nil,
            missionUseMessage: "Chalk and pen marks trace the arterial — follow the line, not the rumors."
        ),
        "item.medkit": ItemDefinition(
            id: "item.medkit",
            displayName: "Medkit",
            category: .medical,
            maxStack: 2,
            systemImageName: "cross.case.fill",
            healFraction: 0.35,
            missionUseMessage: nil
        ),
        "item.energy_bar": ItemDefinition(
            id: "item.energy_bar",
            displayName: "Energy bar",
            category: .supply,
            maxStack: 3,
            systemImageName: "leaf.fill",
            healFraction: 0.08,
            missionUseMessage: nil
        ),
        "item.flashlight": ItemDefinition(
            id: "item.flashlight",
            displayName: "Flashlight",
            category: .tool,
            maxStack: 1,
            systemImageName: "flashlight.on.fill",
            healFraction: nil,
            missionUseMessage: nil
        ),
        "item.stick": ItemDefinition(
            id: "item.stick",
            displayName: "Stick",
            category: .weapon,
            maxStack: 1,
            systemImageName: "figure.fencing",
            healFraction: nil,
            missionUseMessage: nil
        ),
        "item.knife": ItemDefinition(
            id: "item.knife",
            displayName: "Knife",
            category: .weapon,
            maxStack: 1,
            systemImageName: "scissors",
            healFraction: nil,
            missionUseMessage: nil
        ),
        "item.scrap_wire": ItemDefinition(
            id: "item.scrap_wire",
            displayName: "Scrap wire",
            category: .supply,
            maxStack: 5,
            systemImageName: "cable.connector",
            healFraction: nil,
            missionUseMessage: nil
        ),
        "item.tripwire_kit": ItemDefinition(
            id: "item.tripwire_kit",
            displayName: "Tripwire kit",
            category: .tool,
            maxStack: 1,
            systemImageName: "line.diagonal",
            healFraction: nil,
            missionUseMessage: nil
        ),
        "item.reinforced_stick": ItemDefinition(
            id: "item.reinforced_stick",
            displayName: "Reinforced stick",
            category: .weapon,
            maxStack: 1,
            systemImageName: "figure.fencing",
            healFraction: nil,
            missionUseMessage: nil
        ),
    ]
}
