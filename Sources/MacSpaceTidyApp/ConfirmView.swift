import MacSpaceTidyCore
import SwiftUI

/// Shows what will happen before anything changes. Moves and deletes are separate groups,
/// so the user sees which data is kept (moved) and which is removed.
struct ConfirmView: View {
    private static let WIDTH: CGFloat = 560
    private static let MAX_LIST_HEIGHT: CGFloat = 440

    @Bindable var model: AppModel
    @State private var runningApps: [String] = []

    var body: some View {
        let moves = model.selectedItems.filter { $0.action == .move }
        let externalCleans = model.selectedItems.filter { $0.category == .external }
        let trashed = model.selectedItems.filter { $0.action == .trashOnly }
        let deletes = model.selectedItems.filter { $0.action != .move && $0.action != .trashOnly && $0.category != .external }
        VStack(alignment: .leading, spacing: 14) {
            Text("Check what will happen")
                .font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !moves.isEmpty {
                        moveSection(moves)
                    }
                    if !trashed.isEmpty {
                        trashSection(trashed)
                    }
                    if !deletes.isEmpty {
                        deleteSection(deletes)
                    }
                    if !externalCleans.isEmpty {
                        externalSection(externalCleans)
                    }
                }
            }
            .frame(maxHeight: ConfirmView.MAX_LIST_HEIGHT)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(runningApps, id: \.self) { app in
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("\(app) is running. Its items are skipped unless you quit it.")
                    Spacer()
                    Button("Quit \(app)") {
                        RunningApps.quit(named: app)
                        runningApps.removeAll { $0 == app }
                    }
                }
                .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.activeSheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle(hasMoves: !moves.isEmpty, hasDeletes: !deletes.isEmpty || !externalCleans.isEmpty, hasTrashed: !trashed.isEmpty)) { model.optimize() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: ConfirmView.WIDTH)
        .task {
            let items = model.selectedItems
            let names = await Task.detached { Set(items.compactMap(RunningApps.owner)).sorted() }.value
            runningApps = names
        }
    }

    private func moveSection(_ items: [ScanItem]) -> some View {
        section(
            systemImage: "externaldrive.fill",
            tint: .blue,
            title: "Move to external disk — \(count(items, "folder")), \(ByteText.format(total(items)))",
            subtitle: "Nothing is lost. Each folder is copied to the disk, checked, and replaced with a link. "
                + "Apps keep working while the disk is connected."
        ) {
            DiskPickerView(model: model)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 1) {
                    row(item)
                    moveLine(item)
                }
            }
        }
    }

    private func deleteSection(_ items: [ScanItem]) -> some View {
        let isTrash = model.deleteMode == .trash
        return section(
            systemImage: "trash.fill",
            tint: .red,
            title: "Clean — \(count(items, "item")), \(ByteText.format(total(items)))",
            subtitle: isTrash
                ? "What is inside each folder goes to the Trash; the folders stay. You can restore files until you empty the Trash. The space is freed only after that."
                : "What is inside each folder is deleted for good; the folders stay. These are caches that apps rebuild."
        ) {
            Picker("How:", selection: $model.deleteMode) {
                Text("Move to Trash").tag(DeleteMode.trash)
                Text("Delete now").tag(DeleteMode.deleteNow)
            }
            .pickerStyle(.segmented)
            if items.contains(where: \.needsAdmin) {
                note("lock.fill", "Items with a lock need your admin password. They are always deleted now, not to the Trash.")
            }
            if items.contains(where: { $0.action == .deleteSimulatorRuntime }) {
                note("iphone", "Simulator runtimes are always deleted now. Xcode can download them again.")
            }
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func trashSection(_ items: [ScanItem]) -> some View {
        section(
            systemImage: "tray.full.fill",
            tint: .orange,
            title: "To the Trash — \(count(items, "item")), \(ByteText.format(total(items)))",
            subtitle: "These are your own files or data of removed apps. They always go to the Trash, whatever the delete setting is, "
                + "so you can put them back until you empty the Trash."
        ) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func externalSection(_ items: [ScanItem]) -> some View {
        section(
            systemImage: "externaldrive.badge.minus",
            tint: .indigo,
            title: "Clean on external disk — \(count(items, "item")), \(ByteText.format(total(items)))",
            subtitle: "Frees space on the external disk, not on this Mac. Caches are emptied; their folders and links stay. "
                + "Copies that nothing links to are deleted whole. Uses the same Trash or Delete now choice as above."
        ) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func section<Content: View>(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ item: ScanItem) -> some View {
        HStack {
            Text(item.title).lineLimit(1).truncationMode(.middle)
            if item.needsAdmin {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteText.format(item.size.bytes)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// Dry run result for one move: where it goes, or why it cannot start.
    private func moveLine(_ item: ScanItem) -> some View {
        let refusal = model.moveRefusal(item)
        let text = refusal ?? model.usableDiskRoot.map { "→ \(Mover.destination(for: item.path, diskRoot: $0))" } ?? ""
        return Text(text)
            .font(.caption)
            .foregroundStyle(refusal == nil ? Color.secondary : Color.orange)
            .lineLimit(2)
    }

    private func note(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func actionTitle(hasMoves: Bool, hasDeletes: Bool, hasTrashed: Bool) -> String {
        switch (hasMoves, hasDeletes || hasTrashed) {
        case (true, true): return "Move and Clean"
        case (true, false): return "Move"
        default: return hasDeletes && model.deleteMode == .deleteNow ? "Delete" : "Move to Trash"
        }
    }

    private func count(_ items: [ScanItem], _ noun: String) -> String {
        return "\(items.count) \(noun)\(items.count == 1 ? "" : "s")"
    }

    private func total(_ items: [ScanItem]) -> Int64 {
        return items.reduce(0) { $0 + $1.size.bytes }
    }
}
