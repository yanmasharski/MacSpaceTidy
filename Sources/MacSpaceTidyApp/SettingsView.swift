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
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.WIDTH)
    }
}
