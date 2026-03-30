import RealityKit
import SwiftUI

struct GameRootView: View {
    let chapter: ChapterConfig
    var progress: ChapterProgressViewModel

    @State private var viewModel = GameSessionViewModel()
    @State private var sceneController = SideScrollSceneController()
    @State private var showChapterIntro = true

    var body: some View {
        ZStack(alignment: .top) {
            RealityView { content in
                sceneController.attachIfNeeded(
                    insertRoot: { content.add($0) },
                    viewModel: viewModel,
                    chapter: chapter
                )
                content.camera = .virtual
                content.cameraTarget = sceneController.perspectiveCamera
            } update: { _ in
                sceneController.tick(viewModel: viewModel)
            }

            TraversalTouchOverlay(viewModel: viewModel)

            if showChapterIntro {
                chapterIntroOverlay
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(chapter.title)
                    .font(.caption.weight(.semibold))
                Text(chapter.objectiveHUDLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                statusLine
                equippedLine
                if let banner = viewModel.interactBannerText {
                    Text(banner)
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            InventoryHUDView(viewModel: viewModel)
                .padding(.bottom, 96)
        }
        .sheet(isPresented: $viewModel.showCraftingSheet) {
            CraftingSheetView(viewModel: viewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.chapterCompletionToken) { _, _ in
            guard viewModel.chapterCompletionToken > 0 else { return }
            progress.registerCompletion(of: chapter)
            viewModel.flashInteractMessage("Chapter complete — progress saved.")
        }
    }

    private var chapterIntroOverlay: some View {
        VStack(spacing: 16) {
            Text(chapter.title)
                .font(.headline)
            Text(IntroCopy.line(for: chapter.narrativeIntroTextId))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue") {
                showChapterIntro = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .transition(.opacity)
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Label("\(Int(round(viewModel.healthNormalized * 100)))% condition", systemImage: "heart.fill")
            Label(viewModel.isGrounded ? "Grounded" : "Air", systemImage: viewModel.isGrounded ? "figure.stand" : "figure.run")
            if viewModel.isClimbing {
                Label("Climb", systemImage: "arrow.up.and.down")
            }
            if !viewModel.interactPrompt.isEmpty {
                Label(viewModel.interactPrompt, systemImage: "hand.tap")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var equippedLine: some View {
        let w = viewModel.equippedWeaponSummary
        let t = viewModel.equippedToolSummary
        if w != nil || t != nil {
            HStack(spacing: 8) {
                if let w {
                    Label(w, systemImage: "figure.fencing")
                }
                if let t {
                    Label(t, systemImage: "flashlight.on.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// Placeholder narrative until Localizable / string catalog entries exist.
private enum IntroCopy {
    static func line(for textId: String) -> String {
        switch textId {
        case "narrative.ch1.intro":
            return "Lights cut out mid-breath. From the basement you hear the block go quiet — then something in the walls hums wrong."
        case "narrative.ch2.intro":
            return "The neighborhood is holding its breath. Streets funnel toward the arterial; you need a clear run before dark."
        default:
            return ""
        }
    }
}

#Preview {
    NavigationStack {
        GameRootView(chapter: ChapterRegistry.chapters[0], progress: ChapterProgressViewModel())
    }
}
