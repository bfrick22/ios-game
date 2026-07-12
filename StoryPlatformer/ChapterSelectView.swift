import SwiftUI

struct ChapterSelectView: View {
    @Bindable var progress: ChapterProgressViewModel

    /// Conditional rendering instead of NavigationStack/path mutation. Swapping
    /// chapters via this @State + `.id(chapter.id)` guarantees a clean re-init of
    /// GameRootView (and its scene controller) on each chapter transition.
    @State private var currentChapter: ChapterConfig?

    /// Hoisted so inventory, equipped gear, and remembered dialog choices
    /// persist when the player advances from one chapter to the next.
    @State private var sessionViewModel = GameSessionViewModel()

    var body: some View {
        Group {
            if let chapter = currentChapter {
                GameRootView(
                    chapter: chapter,
                    progress: progress,
                    viewModel: sessionViewModel,
                    onAdvance: { next in currentChapter = next },
                    onBack:    { currentChapter = nil }
                )
                .id(chapter.id)   // force a fresh GameRootView when the chapter changes
            } else {
                chapterList
            }
        }
    }

    private var chapterList: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ChapterRegistry.chapters) { chapter in
                        Button {
                            if progress.isUnlocked(chapter) {
                                currentChapter = chapter
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .font(.headline)
                                    Text(chapter.objectiveHUDLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if progress.isUnlocked(chapter) {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(.tint)
                                } else {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(!progress.isUnlocked(chapter))
                    }
                } header: {
                    Text("Chapters")
                } footer: {
                    Text("Complete a chapter to unlock the next.")
                        .font(.caption)
                }
            }
            .navigationTitle("Story Platformer")
        }
    }
}

#Preview {
    ChapterSelectView(progress: ChapterProgressViewModel())
}
