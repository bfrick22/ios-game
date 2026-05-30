import SwiftUI

/// Bottom strip: health, slot row, Use action (touch-friendly).
struct InventoryHUDView: View {
    @Bindable var viewModel: GameSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            healthBar

            HStack(spacing: 10) {
                useButton
                slotStrip
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }

    private var healthBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Condition")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(viewModel.healthNormalized * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(healthGradient)
                        .frame(width: max(8, geo.size.width * CGFloat(viewModel.healthNormalized)))
                }
            }
            .frame(height: 8)
        }
    }

    private var healthGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.75, blue: 0.45),
                Color(red: 0.95, green: 0.55, blue: 0.2),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var slotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0 ..< ItemCatalog.slotCount, id: \.self) { index in
                    slotButton(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slotButton(index: Int) -> some View {
        let selected = viewModel.selectedInventorySlotIndex == index
        let stack = viewModel.inventorySlots[index]
        let def = stack.flatMap { ItemCatalog.definition(for: $0.itemId) }
        let equipped = stack.map { viewModel.isEquipped($0.itemId) } ?? false

        return Button {
            viewModel.selectInventorySlot(index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(slotFill(selected: selected, equipped: equipped))
                if let stack, let def {
                    VStack(spacing: 2) {
                        Image(systemName: def.systemImageName)
                            .font(.body.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                        if stack.quantity > 1 {
                            Text("\(stack.quantity)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    Image(systemName: "square.dashed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(slotBorder(selected: selected, equipped: equipped),
                                  lineWidth: selected || equipped ? 2 : 1)
            )
            // Equipped badge: a green check, distinct from the selection ring.
            .overlay(alignment: .topTrailing) {
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.green)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slotAccessibilityLabel(index: index, stack: stack, def: def))
        .accessibilityValue(equipped ? "Equipped" : "")
    }

    private func slotFill(selected: Bool, equipped: Bool) -> Color {
        if selected { return Color.accentColor.opacity(0.35) }
        if equipped { return Color.green.opacity(0.18) }
        return Color.primary.opacity(0.08)
    }

    private func slotBorder(selected: Bool, equipped: Bool) -> Color {
        if selected { return Color.accentColor.opacity(0.9) }
        if equipped { return Color.green.opacity(0.85) }
        return Color.white.opacity(0.15)
    }

    private func slotAccessibilityLabel(index: Int, stack: InventoryStack?, def: ItemDefinition?) -> String {
        if let stack, let def {
            let qty = stack.quantity > 1 ? " \(stack.quantity)" : ""
            return "Slot \(index + 1), \(def.displayName)\(qty)"
        }
        return "Slot \(index + 1), empty"
    }

    private var useButton: some View {
        Button {
            viewModel.useSelectedInventoryItem()
        } label: {
            Text("Use")
                .font(.subheadline.weight(.semibold))
                .frame(width: 56, height: 44)
                .background(Color.accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use selected item")
    }
}

#Preview {
    InventoryHUDView(viewModel: GameSessionViewModel())
        .padding()
        .background(Color.black.opacity(0.4))
}
