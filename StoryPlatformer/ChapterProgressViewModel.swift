import Foundation
import Observation

@Observable
@MainActor
final class ChapterProgressViewModel {
    private(set) var highestUnlockedChapterIndex: Int

    init() {
        let loaded = GameProgressStore.load()
        let lastOrder = (ChapterRegistry.chapters.map(\.orderIndex).max() ?? 0)
        highestUnlockedChapterIndex = min(max(0, loaded.highestUnlockedChapterIndex), lastOrder)
    }

    func isUnlocked(_ chapter: ChapterConfig) -> Bool {
        chapter.orderIndex <= highestUnlockedChapterIndex
    }

    /// Call when the active chapter’s completion volume fires once per run.
    func registerCompletion(of chapter: ChapterConfig) {
        let lastOrder = ChapterRegistry.chapters.map(\.orderIndex).max() ?? 0
        let candidate = min(max(highestUnlockedChapterIndex, chapter.orderIndex + 1), lastOrder)
        guard candidate > highestUnlockedChapterIndex else { return }
        highestUnlockedChapterIndex = candidate
        persist()
    }

    /// Dev / settings: wipe progress (optional hook).
    func resetProgress() {
        highestUnlockedChapterIndex = 0
        persist()
    }

    private func persist() {
        let payload = PersistedGameProgress(
            highestUnlockedChapterIndex: highestUnlockedChapterIndex,
            saveVersion: PersistedGameProgress.currentSaveVersion
        )
        GameProgressStore.save(payload)
    }
}
