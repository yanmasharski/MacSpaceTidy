import MacSpaceTidyCore
import SwiftUI

/// The duplicate search is its own step: it reads whole files, so it is started by hand and on chosen disks only.
struct DuplicateSearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Find duplicate files", systemImage: "doc.on.doc")
                .font(.headline)
            Text("Compares files of at least \(ByteText.format(ScanOptions.DUPLICATE_MIN_BYTES)). It reads whole files, so it can take a long time on a big disk. Pick where to look.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("This Mac: Desktop, Documents, Movies, Music, Pictures, Downloads", isOn: .constant(true))
                .toggleStyle(.checkbox)
                .disabled(true)
            ForEach(model.diskChoices) { disk in
                Toggle(isOn: Binding(
                    get: { model.duplicateDisks.contains(disk.path) },
                    set: { isOn in
                        if isOn { model.duplicateDisks.insert(disk.path) } else { model.duplicateDisks.remove(disk.path) }
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
                .disabled(disk.problem != nil || model.isScanningDuplicates)
            }
            HStack {
                if model.isScanningDuplicates {
                    ProgressView().controlSize(.small)
                    Text(model.duplicateStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Stop") { model.cancelDuplicates() }
                } else {
                    Button("Scan for duplicates", systemImage: "magnifyingglass") { model.scanDuplicates() }
                        .disabled(model.isScanning)
                    if model.hasSearchedDuplicates && model.report?.items(in: .duplicates).isEmpty == true {
                        Text("No duplicates found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { model.refreshDiskChoices() }
    }
}
