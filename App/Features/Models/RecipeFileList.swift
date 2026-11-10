import KilnCore
import SwiftUI

/// The inset list of files a recipe is made of, one row per component.
struct RecipeFileList: View {
    let components: [ModelRecipe.Component]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(components.enumerated()), id: \.element.role) { index, component in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                RecipeComponentRow(component: component)
            }
        }
        .modelsInsetSurface()
    }
}
