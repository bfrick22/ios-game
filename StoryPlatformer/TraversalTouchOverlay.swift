import SwiftUI

/// Touch-first traversal: virtual stick (move + climb axis), interact, grounded melee, jump.
struct TraversalTouchOverlay: View {
    @Bindable var viewModel: GameSessionViewModel

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
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
        .accessibilityHint(
            viewModel.isClimbing
                ? "Drag to move and climb."
                : "Drag left and right to move forward and back. Drag up and down to move in depth."
        )
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
            Label("Strike", systemImage: "figure.boxing")
                .font(.body.weight(.semibold))
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
        .accessibilityLabel("Melee strike")
        .accessibilityHint("Grounded strike with equipped weapon or fists.")
    }

    private var jumpButton: some View {
        Button {
            viewModel.jumpRequested = true
        } label: {
            Label("Jump", systemImage: "arrow.up.circle.fill")
                .font(.title2.weight(.semibold))
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
                .font(.body.weight(.semibold))
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
