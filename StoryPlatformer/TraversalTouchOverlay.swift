import SwiftUI

/// Touch-first traversal: virtual stick (move), right-side look pad (camera orbit),
/// interact, grounded melee, jump.
struct TraversalTouchOverlay: View {
    @Bindable var viewModel: GameSessionViewModel
    @State private var lastLook: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                // Camera look pad: right portion of the screen, beneath the controls.
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: geo.size.width * 0.45)
                        .allowsHitTesting(false)
                    cameraLookPad
                }

                // Aim reticle: only visible when a ranged weapon is equipped. Sits at
                // the dead center of the screen, where the camera's forward ray lands.
                aimReticle
                    .frame(width: geo.size.width, height: geo.size.height)

                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 0) {
                        virtualStick
                            .frame(width: geo.size.width * 0.42, height: 160 + safe.bottom)
                            .padding(.leading, 12)
                            .padding(.bottom, 8 + safe.bottom * 0.25)

                        Spacer(minLength: 0)
                            .allowsHitTesting(false)

                        VStack(spacing: 14) {
                            interactButton
                            attackButton
                            jumpButton
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 12 + safe.bottom)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    /// Drag anywhere on the right side (away from the action buttons) to orbit the camera.
    private var cameraLookPad: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let dx = Float(value.translation.width - lastLook.width)
                        let dy = Float(value.translation.height - lastLook.height)
                        lastLook = value.translation
                        viewModel.pendingCameraYaw += dx * 0.006     // ~0.34°/pt
                        viewModel.pendingCameraPitch += dy * 0.004
                        viewModel.isLookingActive = true
                    }
                    .onEnded { _ in
                        lastLook = .zero
                        viewModel.isLookingActive = false
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Look")
            .accessibilityHint("Drag to move the camera.")
    }

    private var virtualStick: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .frame(width: 140, height: 140)
            Circle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 56, height: 56)
                .offset(stickKnobOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let maxR: CGFloat = 70
                    var x = Float(value.translation.width / maxR)
                    var y = Float(value.translation.height / maxR)
                    let m = hypot(x, y)
                    if m > 1 {
                        x /= m
                        y /= m
                    }
                    viewModel.horizontalInput = x
                    viewModel.verticalInput = y
                }
                .onEnded { _ in
                    viewModel.horizontalInput = 0
                    viewModel.verticalInput = 0
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move")
        .accessibilityHint("Drag to move. Up is forward, down is back, left and right turn.")
    }

    private var stickKnobOffset: CGSize {
        let r: CGFloat = 52
        let dx = CGFloat(viewModel.horizontalInput) * r
        let dy = CGFloat(viewModel.verticalInput) * r
        return CGSize(width: dx, height: dy)
    }

    private var attackButton: some View {
        Button {
            viewModel.attackRequested = true
        } label: {
            Label(attackLabelText, systemImage: attackLabelIcon)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(width: 72, height: 56)
                .background(
                    viewModel.isGrounded && !viewModel.isClimbing
                        ? Color.orange.opacity(0.35)
                        : Color.gray.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isGrounded || viewModel.isClimbing)
        .accessibilityLabel(viewModel.equippedRangedWeaponId != nil ? "Fire" : "Melee strike")
        .accessibilityHint(viewModel.equippedRangedWeaponId != nil
            ? "Fires the equipped ranged weapon."
            : "Grounded strike with equipped weapon or fists.")
    }

    private var attackLabelText: String {
        viewModel.equippedRangedWeaponId != nil ? "Fire" : "Strike"
    }

    private var attackLabelIcon: String {
        viewModel.equippedRangedWeaponId != nil ? "scope" : "figure.boxing"
    }

    /// Center-screen reticle: shows where the bullet will go (camera-forward aim).
    /// Only visible when a ranged weapon is equipped.
    @ViewBuilder
    private var aimReticle: some View {
        if viewModel.equippedRangedWeaponId != nil {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1.4)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 3, height: 3)
            }
            .shadow(color: .black.opacity(0.55), radius: 2)
            .allowsHitTesting(false)
        }
    }

    private var jumpButton: some View {
        Button {
            viewModel.jumpRequested = true
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                Text("Jump")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 72, height: 72)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump")
    }

    private var interactButton: some View {
        Button {
            viewModel.interactRequested = true
        } label: {
            Label("Interact", systemImage: "hand.tap.fill")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(width: 72, height: 56)
                .background(viewModel.interactPrompt.isEmpty ? Color.gray.opacity(0.35) : Color.accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.interactPrompt.isEmpty)
        .accessibilityLabel("Interact")
        .accessibilityValue(viewModel.interactPrompt.isEmpty ? "Nothing nearby" : viewModel.interactPrompt)
    }
}
