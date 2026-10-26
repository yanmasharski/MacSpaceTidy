import MacSpaceTidyCore
import SwiftUI

/// A category the scan has not counted yet. Dimmed and pulsing until its numbers arrive.
struct PendingCategoryView: View {
    let category: ItemCategory

    @State private var isDim = false

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 14)
            Circle().fill(CategoryColors.color(category)).frame(width: 10, height: 10)
            Text(category.title).font(.headline)
            Spacer()
            ProgressView().controlSize(.small)
            Text("counting…").foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .opacity(isDim ? 0.35 : 0.75)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isDim = true }
        }
    }
}
