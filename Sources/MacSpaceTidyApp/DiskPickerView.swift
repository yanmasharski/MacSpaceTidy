import MacSpaceTidyCore
import SwiftUI

/// Picks the external disk for moves. Disks with a problem (exFAT, read-only) are shown but cannot be chosen.
struct DiskPickerView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Move to:", selection: $model.moveDiskRoot) {
                Text("Choose a disk").tag(String?.none)
                ForEach(model.diskChoices) { disk in
                    Text("\(disk.name) — \(ByteText.format(disk.freeBytes)) free, \(disk.fileSystem)")
                        .tag(Optional(disk.path))
                        .selectionDisabled(disk.problem != nil)
                }
            }
            if model.diskChoices.isEmpty {
                Text("No external disk is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.diskChoices.filter { $0.problem != nil }) { disk in
                Text("\(disk.name): \(disk.problem ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refreshDiskChoices() }
    }
}
