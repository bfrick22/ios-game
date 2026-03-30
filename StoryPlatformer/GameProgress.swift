import Foundation

/// Local save payload; extend with inventory / mission flags later.
struct PersistedGameProgress: Codable, Sendable, Equatable {
    /// Highest chapter **orderIndex** the player may start (sequential unlock).
    var highestUnlockedChapterIndex: Int
    var saveVersion: Int

    static let currentSaveVersion = 1

    static var newGame: PersistedGameProgress {
        PersistedGameProgress(highestUnlockedChapterIndex: 0, saveVersion: currentSaveVersion)
    }
}

@MainActor
enum GameProgressStore {
    private static let fileName = "game_progress.json"

    private static var fileURL: URL {
        let base = URL.applicationSupportDirectory
        if !FileManager.default.fileExists(atPath: base.path()) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appending(path: fileName, directoryHint: .notDirectory)
    }

    static func load() -> PersistedGameProgress {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return .newGame
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PersistedGameProgress.self, from: data)
            if decoded.saveVersion != PersistedGameProgress.currentSaveVersion {
                return migrate(from: decoded)
            }
            return decoded
        } catch {
            return .newGame
        }
    }

    static func save(_ progress: PersistedGameProgress) {
        do {
            let data = try JSONEncoder().encode(progress)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Intentionally quiet; gameplay continues. Could log in debug builds.
        }
    }

    private static func migrate(from old: PersistedGameProgress) -> PersistedGameProgress {
        PersistedGameProgress(
            highestUnlockedChapterIndex: max(0, old.highestUnlockedChapterIndex),
            saveVersion: PersistedGameProgress.currentSaveVersion
        )
    }
}
