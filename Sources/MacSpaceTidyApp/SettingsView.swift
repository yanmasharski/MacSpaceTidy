import SwiftUI

struct SettingsView: View {
    private static let WIDTH: CGFloat = 460

    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                DiskPickerView(model: model)
                Text("Moved folders go to a MacSpaceTidy folder on this disk. Their links break when the disk is not connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("External disk")
            }
            Section {
                ForEach(model.diskChoices.filter { $0.problem == nil }) { disk in
                    Toggle(disk.name, isOn: Binding(
                        get: { model.extraScanDisks.contains(disk.path) },
                        set: { isOn in
                            if isOn { model.extraScanDisks.insert(disk.path) } else { model.extraScanDisks.remove(disk.path) }
                        }
                    ))
                }
                Text(model.diskChoices.contains { $0.problem == nil }
                    ? "Large files and duplicates are searched on this Mac. Tick a disk to search it too. Off by default; it reads many files, so the next scan takes longer."
                    : "No other disk is connected. Large files and duplicates are searched on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Also search these disks")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshDiskChoices() }
        .frame(width: SettingsView.WIDTH)
    }
}
