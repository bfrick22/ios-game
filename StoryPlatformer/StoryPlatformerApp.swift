import SwiftUI

@main
struct StoryPlatformerApp: App {
    @State private var chapterProgress = ChapterProgressViewModel()

    var body: some Scene {
        WindowGroup {
            ChapterSelectView(progress: chapterProgress)
        }
    }
}
