import Foundation

/// Grounded melee only — damage per strike vs normalized enemy health (0…1 scale).
enum MeleeCombat {
    static let unarmedStrikeDamage: Float = 0.12

    static func strikeDamage(equippedWeaponItemId: String?) -> Float {
        guard let id = equippedWeaponItemId,
              let def = ItemCatalog.definition(for: id),
              def.category == .weapon,
              let w = def.meleeDamage
        else {
            return unarmedStrikeDamage
        }
        return w
    }
}
