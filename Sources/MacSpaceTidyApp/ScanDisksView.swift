import MacSpaceTidyCore
import SwiftUI

/// A list of connected disks, one checkbox each. Every ticked disk is also searched for large files and duplicates.
/// Shown in the main window, so the choice is easy to find. Applies on the next scan.
struct ScanDisksView: View {
    @Bindable var model: AppModel

    var body: some View {
        if !model.diskChoices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Extra scan: other disks", systemImage: "externaldrive.badge.plus")
                    .font(.headline)
                Text("Large files and duplicates are always searched on this Mac. Tick any disks you want searched too. Takes effect on the next scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.diskChoices) { disk in
                    Toggle(isOn: Binding(
                        get: { model.extraScanDisks.contains(disk.path) },
                        set: { isOn in
                            if isOn { model.extraScanDisks.insert(disk.path) } else { model.extraScanDisks.remove(disk.path) }
                        }
                    )) {
                        HStack {
                            Text(disk.name)
                            Text(disk.problem ?? "\(ByteText.format(disk.freeBytes)) free")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(disk.problem != nil)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .onAppear { model.refreshDiskChoices() }
        }
    }
}
