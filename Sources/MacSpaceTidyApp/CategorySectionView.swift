import MacSpaceTidyCore
import SwiftUI

struct CategorySectionView: View {
    let model: AppModel
    let category: ItemCategory
    let items: [ScanItem]
    let totalBytes: Int64

    @State private var isExpanded: Bool

    init(model: AppModel, category: ItemCategory, items: [ScanItem], totalBytes: Int64) {
        self.model = model
        self.category = category
        self.items = items
        self.totalBytes = totalBytes
        _isExpanded = State(initialValue: model.initiallyExpanded.contains(category))
    }

    var body: some View {
        let selectable = items.filter(PlanSelection.isSelectable)
        let selectedCount = selectable.filter { model.plan.isSelected($0) }.count
        let largestBytes = items.map(\.size.bytes).max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
                CheckboxView(state: checkState(selected: selectedCount, total: selectable.count), isEnabled: !selectable.isEmpty) {
                    model.plan.setSelected(selectable, selectedCount < selectable.count)
                }
                Circle().fill(CategoryColors.color(category)).frame(width: 10, height: 10)
                Text(category.title).font(.headline)
                Text("\(items.count)").foregroundStyle(.secondary)
                Spacer()
                let isPending = model.pendingCategories.contains(category)
                let isCounting = isPending || (model.isScanningExternal && (category == .alreadyMoved || category == .external))
                if isCounting {
                    ProgressView().controlSize(.small)
                    Text(isPending ? "counting…" : (totalBytes > 0 ? "last scan, counting again…" : "measuring…")).foregroundStyle(.orange)
                }
                if !isCounting || totalBytes > 0 {
                    Text((isCounting && !isPending ? "~ " : "") + ByteText.format(totalBytes)).monospacedDigit()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }

            if isExpanded {
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        if item.category == .duplicates {
                            DuplicateGroupView(model: model, item: item)
                        } else {
                            ItemRowView(model: model, item: item, largestBytes: largestBytes)
                        }
                        Divider().padding(.leading, 58)
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func checkState(selected: Int, total: Int) -> CheckboxView.State {
        if selected == 0 {
            return .off
        }
        return selected == total ? .on : .mixed
    }
}
