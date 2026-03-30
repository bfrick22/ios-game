import Foundation
import Observation

/// Session state for the active play segment; gameplay systems read/write plain Swift data here.
@Observable
@MainActor
final class GameSessionViewModel {
    /// Fixed small inventory (plan: 8–12 slots).
    private(set) var inventorySlots: [InventoryStack?] = Array(repeating: nil, count: ItemCatalog.slotCount)

    /// Highlighted slot for Use; tap same slot again to keep selection.
    var selectedInventorySlotIndex: Int?

    /// 0…1 — medical/supply consume adjusts this; future combat can read it.
    var healthNormalized: Float = 1

    /// Improvised melee selection for future combat pipeline.
    private(set) var equippedWeaponItemId: String?

    /// Tool selection (flashlight, etc.) for future interact/lighting.
    private(set) var equippedToolItemId: String?

    var equippedWeaponSummary: String? {
        guard let id = equippedWeaponItemId, let def = ItemCatalog.definition(for: id), def.category == .weapon else { return nil }
        return def.displayName
    }

    var equippedToolSummary: String? {
        guard let id = equippedToolItemId, let def = ItemCatalog.definition(for: id), def.category == .tool else { return nil }
        return def.displayName
    }

    /// -1…1 from virtual stick / keyboard; movement on the play plane (X).
    var horizontalInput: Float = 0

    /// -1…1 from stick vertical; used while inside a climb volume (ladder).
    var verticalInput: Float = 0

    var jumpRequested: Bool = false

    var interactRequested: Bool = false

    /// Set by the scene each frame from horizontal input; melee strikes forward on this axis (±1).
    var facingSign: Float = 1

    var attackRequested: Bool = false

    /// Short hint near an interactable (empty when out of range).
    var interactPrompt: String = ""

    /// Last-frame simulation flags for HUD / control hints.
    var isGrounded: Bool = false
    var isClimbing: Bool = false

    /// Brief feedback after a successful interact.
    var interactBannerText: String?

    /// Increments when the chapter completion volume is entered (once per run).
    private(set) var chapterCompletionToken: Int = 0

    /// Story beats completed this chapter run; gates whitelist recipes (`CraftRecipe.requiredStoryBeatId`).
    private(set) var completedStoryBeatIds: Set<String> = []

    /// Set each frame by `SideScrollSceneController` when the player is in range of a workbench.
    var nearWorkstationId: String?

    /// Opened from interact at a crafting workstation.
    var showCraftingSheet: Bool = false

    func notifyChapterCompleted() {
        chapterCompletionToken += 1
    }

    func resetChapterCompletionSignal() {
        chapterCompletionToken = 0
    }

    /// Clears per-chapter run state when loading a segment (inventory is unchanged).
    func resetSessionForNewChapter() {
        completedStoryBeatIds.removeAll()
        nearWorkstationId = nil
        showCraftingSheet = false
        resetChapterCompletionSignal()
        attackRequested = false
    }

    func applyDamageFromHostile(normalizedAmount: Float) {
        let a = max(0, normalizedAmount)
        healthNormalized = max(0, healthNormalized - a)
    }

    /// Removes one unit from the first matching stack (crafting / traps).
    @discardableResult
    func consumeOneItem(itemId: String) -> Bool {
        for i in inventorySlots.indices {
            guard var stack = inventorySlots[i], stack.itemId == itemId, stack.quantity > 0 else { continue }
            stack.quantity -= 1
            inventorySlots[i] = stack.quantity > 0 ? stack : nil
            return true
        }
        return false
    }

    func registerStoryBeatCompleted(_ storyBeatId: String) {
        completedStoryBeatIds.insert(storyBeatId)
    }

    func countItem(_ itemId: String) -> Int {
        inventorySlots.compactMap { $0 }.filter { $0.itemId == itemId }.reduce(0) { $0 + $1.quantity }
    }

    /// Whitelist recipes only; no discovery or tech trees.
    func canCraftRecipe(_ recipe: CraftRecipe) -> Bool {
        if let storyId = recipe.requiredStoryBeatId, !completedStoryBeatIds.contains(storyId) {
            return false
        }
        if let ws = recipe.requiredWorkstationId {
            guard nearWorkstationId == ws else { return false }
        }
        for ing in recipe.ingredients {
            if countItem(ing.itemId) < ing.quantity { return false }
        }
        return true
    }

    func craftStatusLine(for recipe: CraftRecipe) -> String {
        if let storyId = recipe.requiredStoryBeatId, !completedStoryBeatIds.contains(storyId) {
            return "Need story progress"
        }
        if let ws = recipe.requiredWorkstationId, nearWorkstationId != ws {
            return "Use a workbench"
        }
        for ing in recipe.ingredients {
            if countItem(ing.itemId) < ing.quantity {
                return "Missing materials"
            }
        }
        return "Ready"
    }

    @discardableResult
    func attemptCraftRecipe(recipeId: String) -> Bool {
        guard let recipe = RecipeCatalog.recipe(id: recipeId) else { return false }
        guard canCraftRecipe(recipe) else { return false }

        let snapshot = inventorySlots
        guard removeIngredients(recipe.ingredients) else { return false }

        if addItemIfPossible(itemId: recipe.outputItemId, quantity: recipe.outputQuantity) {
            flashInteractMessage("Crafted \(recipe.displayName).")
            return true
        }

        inventorySlots = snapshot
        flashInteractMessage("Inventory full — make room for the result.")
        return false
    }

    private func removeIngredients(_ ingredients: [CraftIngredient]) -> Bool {
        for ing in ingredients {
            if countItem(ing.itemId) < ing.quantity { return false }
        }
        for ing in ingredients {
            var remaining = ing.quantity
            for i in inventorySlots.indices {
                guard var stack = inventorySlots[i], stack.itemId == ing.itemId else { continue }
                let take = min(stack.quantity, remaining)
                stack.quantity -= take
                remaining -= take
                inventorySlots[i] = stack.quantity > 0 ? stack : nil
                if remaining == 0 { break }
            }
            if remaining > 0 { return false }
        }
        return true
    }

    func flashInteractMessage(_ text: String) {
        interactBannerText = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if interactBannerText == text {
                interactBannerText = nil
            }
        }
    }

    func selectInventorySlot(_ index: Int) {
        guard inventorySlots.indices.contains(index) else { return }
        if selectedInventorySlotIndex == index {
            selectedInventorySlotIndex = nil
        } else {
            selectedInventorySlotIndex = index
        }
    }

    /// Merges into matching stacks when stackable; uses first empty slots otherwise.
    /// Grants multiple distinct items atomically (story beats); rolls back if any add fails.
    @discardableResult
    func addItemsAtomicallyIfPossible(itemIds: [String]) -> Bool {
        let snapshot = inventorySlots
        for itemId in itemIds {
            if !addItemIfPossible(itemId: itemId, quantity: 1) {
                inventorySlots = snapshot
                return false
            }
        }
        return true
    }

    @discardableResult
    func addItemIfPossible(itemId: String, quantity: Int = 1) -> Bool {
        guard let def = ItemCatalog.definition(for: itemId), quantity > 0 else { return false }

        var remaining = quantity

        if def.maxStack > 1 {
            for i in inventorySlots.indices {
                guard var stack = inventorySlots[i], stack.itemId == itemId else { continue }
                let room = def.maxStack - stack.quantity
                let take = min(room, remaining)
                guard take > 0 else { continue }
                stack.quantity += take
                inventorySlots[i] = stack
                remaining -= take
                if remaining == 0 { return true }
            }
        }

        while remaining > 0 {
            guard let empty = inventorySlots.firstIndex(where: { $0 == nil }) else { return false }
            let chunk = min(def.maxStack, remaining)
            inventorySlots[empty] = InventoryStack(itemId: itemId, quantity: chunk)
            remaining -= chunk
        }
        return true
    }

    func useSelectedInventoryItem() {
        guard let idx = selectedInventorySlotIndex else {
            flashInteractMessage("Select a slot first.")
            return
        }
        guard var stack = inventorySlots[idx], let def = ItemCatalog.definition(for: stack.itemId) else {
            flashInteractMessage("Empty slot.")
            return
        }

        switch def.category {
        case .medical:
            let delta = def.healFraction ?? 0.25
            healthNormalized = min(1, healthNormalized + delta)
            stack.quantity -= 1
            inventorySlots[idx] = stack.quantity > 0 ? stack : nil
            flashInteractMessage("Used \(def.displayName).")

        case .supply:
            let delta = def.healFraction ?? 0
            if delta > 0 {
                healthNormalized = min(1, healthNormalized + delta)
            }
            stack.quantity -= 1
            inventorySlots[idx] = stack.quantity > 0 ? stack : nil
            flashInteractMessage(delta > 0 ? "Finished \(def.displayName). A little steadier." : "Used \(def.displayName).")

        case .weapon:
            if equippedWeaponItemId == stack.itemId {
                equippedWeaponItemId = nil
                flashInteractMessage("Holstered \(def.displayName).")
            } else {
                equippedWeaponItemId = stack.itemId
                flashInteractMessage("Equipped \(def.displayName).")
            }

        case .tool:
            if equippedToolItemId == stack.itemId {
                equippedToolItemId = nil
                flashInteractMessage("Stowed \(def.displayName).")
            } else {
                equippedToolItemId = stack.itemId
                flashInteractMessage("Equipped \(def.displayName).")
            }

        case .mission:
            flashInteractMessage(def.missionUseMessage ?? "\(def.displayName) — needed for the route ahead.")
        }
    }
}
