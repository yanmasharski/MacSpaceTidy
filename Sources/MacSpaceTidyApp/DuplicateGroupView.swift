import MacSpaceTidyCore
import SwiftUI

/// A group of identical files. The user picks the copy that stays; ticking the box sends the others to the Trash.
struct DuplicateGroupView: View {
    let model: AppModel
    let item: ScanItem

    var body: some View {
        let isChecked = model.plan.isSelected(item)
        let keeper = model.plan.keeperIndex(of: item)
        HStack(alignment: .top, spacing: 10) {
            CheckboxView(state: isChecked ? .on : .off, isEnabled: true) {
                model.plan.toggle(item)
            }
            .padding(.leading, 34)
            .help("Tick to send the other copies to the Trash. Leave it empty to keep all copies.")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("Frees " + ByteText.format(item.size.bytes)).monospacedDigit().foregroundStyle(.secondary)
                }
                Text(isChecked
                    ? "The copies marked “To the Trash” go to the Trash. The copy you keep stays where it is."
                    : "Choose the copy to keep, then tick the box. If you leave the box empty, all copies stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(item.duplicateCopies.enumerated()), id: \.offset) { index, copy in
                    copyRow(index: index, copy: copy, isKept: index == keeper, isChecked: isChecked)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
    }

    private func copyRow(index: Int, copy: DuplicateCopy, isKept: Bool, isChecked: Bool) -> some View {
        Button {
            model.plan.setKeeper(of: item, to: index)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isKept ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isKept ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Copy \(index + 1) · \(copy.diskName ?? "This Mac")" + (index == 0 ? " · suggested" : ""))
                    Text(PathTools.abbreviate(copy.path, home: NSHomeDirectory()) + (copy.modified.map { " · changed \(RelativeTime.ago($0))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if isChecked && !isKept {
                    Label("To the Trash", systemImage: "trash").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Stays").font(.caption).foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Keep this copy.")
    }
}
