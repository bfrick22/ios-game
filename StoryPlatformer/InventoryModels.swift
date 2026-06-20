import Foundation

enum ItemCategory: String, Codable, Sendable, Hashable {
    case tool
    case weapon
    case medical
    case supply
    case mission
    case apparel
}

/// Equippable apparel slots; each maps to a region of the player rig.
enum GearSlot: String, Codable, Sendable, Hashable {
    case shirt   // torso + sleeves
    case pants   // legs
    case gloves  // hands
    case mask    // head-gear mount
}

/// UIKit-free color for designer data; converted to a material at build time.
struct RGBColor: Sendable, Hashable, Equatable {
    var r: Float
    var g: Float
    var b: Float
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
    /// Weapon: damage per grounded melee strike (normalized 0…1 vs enemy).
    var meleeDamage: Float?
    /// Weapon (ranged): damage per shot (normalized 0…1 vs enemy).
    var rangedDamage: Float? = nil
    /// Weapon (ranged): rounds available before going dry (no reload system yet).
    var magazineCapacity: Int? = nil
    /// Apparel: which rig slot this equips to.
    var gearSlot: GearSlot? = nil
    /// Apparel: color applied to the slot's parts (or the mask mesh).
    var gearColor: RGBColor? = nil
    /// Apparel boost: fraction of incoming damage this piece resists (0…1).
    /// Placeholder boost model — gear "does something" via light damage resistance.
    var armor: Float? = nil
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
            missionUseMessage: "Your go-bag is packed for a hard exit — keep it close until you are clear.",
            meleeDamage: nil
        ),
        "item.route_map": ItemDefinition(
            id: "item.route_map",
            displayName: "Marked map",
            category: .mission,
            maxStack: 1,
            systemImageName: "map.fill",
            healFraction: nil,
            missionUseMessage: "Chalk and pen marks trace the arterial — follow the line, not the rumors.",
            meleeDamage: nil
        ),
        "item.medkit": ItemDefinition(
            id: "item.medkit",
            displayName: "Medkit",
            category: .medical,
            maxStack: 2,
            systemImageName: "cross.case.fill",
            healFraction: 0.35,
            missionUseMessage: nil,
            meleeDamage: nil
        ),
        "item.energy_bar": ItemDefinition(
            id: "item.energy_bar",
            displayName: "Energy bar",
            category: .supply,
            maxStack: 3,
            systemImageName: "leaf.fill",
            healFraction: 0.08,
            missionUseMessage: nil,
            meleeDamage: nil
        ),
        "item.flashlight": ItemDefinition(
            id: "item.flashlight",
            displayName: "Flashlight",
            category: .tool,
            maxStack: 1,
            systemImageName: "flashlight.on.fill",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil
        ),
        "item.stick": ItemDefinition(
            id: "item.stick",
            displayName: "Stick",
            category: .weapon,
            maxStack: 1,
            systemImageName: "figure.fencing",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: 0.16
        ),
        "item.knife": ItemDefinition(
            id: "item.knife",
            displayName: "Knife",
            category: .weapon,
            maxStack: 1,
            systemImageName: "fork.knife",          // reliable SF Symbol that reads as a knife
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: 0.55                       // deep wound — close to a 2-hit kill
        ),
        "item.scrap_wire": ItemDefinition(
            id: "item.scrap_wire",
            displayName: "Scrap wire",
            category: .supply,
            maxStack: 5,
            systemImageName: "cable.connector",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil
        ),
        "item.tripwire_kit": ItemDefinition(
            id: "item.tripwire_kit",
            displayName: "Tripwire kit",
            category: .tool,
            maxStack: 1,
            systemImageName: "line.diagonal",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil
        ),
        "item.reinforced_stick": ItemDefinition(
            id: "item.reinforced_stick",
            displayName: "Reinforced stick",
            category: .weapon,
            maxStack: 1,
            systemImageName: "figure.fencing",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: 0.3
        ),
        "item.baton": ItemDefinition(
            id: "item.baton",
            displayName: "Baton",
            category: .weapon,
            maxStack: 1,
            systemImageName: "hammer.fill",         // reliable SF Symbol — reads as blunt instrument
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: 0.22                       // blunt force — several hits to drop a target
        ),
        // Gun: grounded post-EMP firearm. Ranged via hitscan; finite magazine, no
        // reload yet (running dry is the limit). Pistol-whip damage is the melee fallback.
        "item.pistol": ItemDefinition(
            id: "item.pistol",
            displayName: "Pistol",
            category: .weapon,
            maxStack: 1,
            systemImageName: "scope",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: 0.14,
            rangedDamage: 0.7,
            magazineCapacity: 12
        ),
        // ── Apparel (equippable; recolors the matching rig parts) ─────────────
        "item.work_shirt": ItemDefinition(
            id: "item.work_shirt",
            displayName: "Work shirt",
            category: .apparel,
            maxStack: 1,
            systemImageName: "tshirt.fill",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil,
            gearSlot: .shirt,
            gearColor: RGBColor(r: 0.20, g: 0.46, b: 0.55),
            armor: 0.10
        ),
        "item.cargo_pants": ItemDefinition(
            id: "item.cargo_pants",
            displayName: "Cargo pants",
            category: .apparel,
            maxStack: 1,
            systemImageName: "figure.walk",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil,
            gearSlot: .pants,
            gearColor: RGBColor(r: 0.42, g: 0.40, b: 0.26),
            armor: 0.06
        ),
        "item.work_gloves": ItemDefinition(
            id: "item.work_gloves",
            displayName: "Work gloves",
            category: .apparel,
            maxStack: 1,
            systemImageName: "hand.raised.fill",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil,
            gearSlot: .gloves,
            gearColor: RGBColor(r: 0.30, g: 0.18, b: 0.10),
            armor: 0.03
        ),
        "item.balaclava": ItemDefinition(
            id: "item.balaclava",
            displayName: "Balaclava",
            category: .apparel,
            maxStack: 1,
            systemImageName: "theatermasks.fill",
            healFraction: nil,
            missionUseMessage: nil,
            meleeDamage: nil,
            gearSlot: .mask,
            gearColor: RGBColor(r: 0.09, g: 0.09, b: 0.11),
            armor: 0.05
        ),
    ]
}
