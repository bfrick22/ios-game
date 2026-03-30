import SwiftUI

struct ChapterSelectView: View {
    @Bindable var progress: ChapterProgressViewModel
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(ChapterRegistry.chapters) { chapter in
                        Button {
                            if progress.isUnlocked(chapter) {
                                path.append(chapter)
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
            .navigationDestination(for: ChapterConfig.self) { chapter in
                GameRootView(chapter: chapter, progress: progress)
            }
        }
    }
}

#Preview {
    ChapterSelectView(progress: ChapterProgressViewModel())
}
