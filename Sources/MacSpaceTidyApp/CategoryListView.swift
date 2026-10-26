import MacSpaceTidyCore
import SwiftUI

struct CategoryListView: View {
    let model: AppModel
    let report: ScanReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ItemCategory.allCases.filter { $0 != .system }, id: \.self) { category in
                let items = report.items(in: category)
                if items.isEmpty && model.pendingCategories.contains(category) {
                    PendingCategoryView(category: category)
                } else if !items.isEmpty {
                    CategorySectionView(model: model, category: category, items: items, totalBytes: report.totalBytes(in: category))
                }
            }
        }
    }
}
