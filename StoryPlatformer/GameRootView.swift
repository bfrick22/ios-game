import QuartzCore
import RealityKit
import SwiftUI

struct GameRootView: View {
    let chapter: ChapterConfig
    var progress: ChapterProgressViewModel

    @State private var viewModel = GameSessionViewModel()
    @State private var sceneController = ThirdPersonSceneController()
    @State private var frameClock = FrameClock()
    @State private var showChapterIntro = true
    @State private var inventoryExpanded = false

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let controlBand = Self.controlBandHeight(safeBottom: safe.bottom)
            ZStack {
                RealityView { content in
                    sceneController.attachIfNeeded(
                        insertRoot: { content.add($0) },
                        viewModel: viewModel,
                        chapter: chapter
                    )
                    content.camera = .virtual
                    content.cameraTarget = sceneController.perspectiveCamera
                } update: { _ in
                    // Do not run gameplay tick here: `update` only runs when SwiftUI invalidates this view,
                    // so physics/camera would freeze between input changes. The CADisplayLink below drives simulation.
                }
                // RealityKit’s embedded view otherwise wins hit testing; controls must sit above and receive touches.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                TraversalTouchOverlay(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Above the controls so the Bag button stays tappable over the look pad.
                inventoryOverlay(safe: safe, controlBand: controlBand)

                if viewModel.activeDialog != nil {
                    dialogOverlay
                }

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: showChapterIntro) { _, shown in
            if shown {
                frameClock.stop()
            } else {
                frameClock.start { sceneController.tick(viewModel: viewModel) }
            }
        }
        .sheet(isPresented: $viewModel.showCraftingSheet) {
            CraftingSheetView(viewModel: viewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.chapterCompletionToken) { _, _ in
            guard viewModel.chapterCompletionToken > 0 else { return }
            progress.registerCompletion(of: chapter)
            viewModel.flashInteractMessage("Chapter complete — progress saved.")
        }
        .onDisappear {
            frameClock.stop()
            sceneController.teardown()
        }
    }

    /// Matches `TraversalTouchOverlay` bottom layout (stick column vs action stack) plus a small gap above the strip.
    private static func controlBandHeight(safeBottom: CGFloat) -> CGFloat {
        let leftColumn = 160 + safeBottom + 8 + safeBottom * 0.25
        let rightColumn = 56 + 14 + 56 + 14 + 72 + 12 + safeBottom
        return max(leftColumn, rightColumn) + 8
    }

    @ViewBuilder
    private func inventoryOverlay(safe: EdgeInsets, controlBand: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer()
            if inventoryExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            inventoryExpanded = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bag.fill")
                                Text("Bag")
                                Image(systemName: "chevron.down")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close inventory")
                    }
                    InventoryHUDView(viewModel: viewModel)
                }
            } else {
                HStack {
                    Spacer()
                    Button {
                        inventoryExpanded = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bag.fill")
                            Text("Bag")
                            Image(systemName: "chevron.up")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open inventory")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, controlBand)
        .padding(.leading, safe.leading + 10)
        .padding(.trailing, safe.trailing + 10)
    }

    @ViewBuilder
    private var dialogOverlay: some View {
        if let dialog = viewModel.activeDialog {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())  // capture taps so controls below are inert

                VStack(alignment: .leading, spacing: 14) {
                    Text(dialog.speaker)
                        .font(.headline)
                    Text(dialog.line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if dialog.choices.isEmpty {
                        Button("Leave") {
                            viewModel.dialogCloseRequested = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        HStack(spacing: 12) {
                            ForEach(dialog.choices) { choice in
                                Button(choice.label) {
                                    viewModel.pendingDialogChoiceId = choice.id
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 460)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .transition(.opacity)
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
        let armor = viewModel.totalArmor
        if w != nil || t != nil || armor > 0 {
            HStack(spacing: 8) {
                if let w {
                    Label(w, systemImage: "figure.fencing")
                }
                if let t {
                    Label(t, systemImage: "flashlight.on.fill")
                }
                if armor > 0 {
                    Label("\(Int(round(armor * 100)))% armor", systemImage: "shield.lefthalf.filled")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// Vsync-synced game-loop driver. CADisplayLink fires once per display refresh (60 or 120 Hz),
/// giving even frame pacing — far smoother than a run-loop `Timer`, which jitters and coalesces.
@MainActor
final class FrameClock: NSObject {
    private var link: CADisplayLink?
    private var onFrame: (() -> Void)?

    func start(_ onFrame: @escaping () -> Void) {
        stop()
        self.onFrame = onFrame
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func step() {
        onFrame?()
    }
}

/// Placeholder narrative until Localizable / string catalog entries exist.
private enum IntroCopy {
    static func line(for textId: String) -> String {
        switch textId {
        case "narrative.tutorial.intro":
            return "Welcome to the gym. Left stick to run — push gently to walk, fully to sprint. Weave the training dummies, clear the hurdle, grab the supplies, and reach the exit doors."
        case "narrative.ch1.intro":
            return "The factory grid is still running. Blue neon marks the safe path — red is drone territory. Reach the server room before they lock you out."
        case "narrative.ch2.intro":
            return "The drones are adapting their patrol routes. Find the workbench, craft what you need, and reach the arterial exit."
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
