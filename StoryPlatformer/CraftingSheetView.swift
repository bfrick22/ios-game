import SwiftUI

/// Simple whitelist crafting UI — no tech tree or material farming.
struct CraftingSheetView: View {
    @Bindable var viewModel: GameSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Recipes are fixed and story-gated. Gather marked materials at a workbench.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Recipes") {
                    ForEach(RecipeCatalog.all, id: \.id) { recipe in
                        recipeRow(recipe)
                    }
                }
            }
            .navigationTitle("Craft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.showCraftingSheet = false
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: CraftRecipe) -> some View {
        let ready = viewModel.canCraftRecipe(recipe)
        let status = viewModel.craftStatusLine(for: recipe)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recipe.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(ready ? .secondary : .orange)
            }
            Text(ingredientSummary(recipe))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                viewModel.attemptCraftRecipe(recipeId: recipe.id)
            } label: {
                Text("Craft")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ready)
        }
        .padding(.vertical, 4)
    }

    private func ingredientSummary(_ recipe: CraftRecipe) -> String {
        recipe.ingredients.map { ing in
            let name = ItemCatalog.definition(for: ing.itemId)?.displayName ?? ing.itemId
            let have = viewModel.countItem(ing.itemId)
            return "\(name) \(have)/\(ing.quantity)"
        }.joined(separator: " · ")
    }
}

#Preview {
    CraftingSheetView(viewModel: GameSessionViewModel())
}
