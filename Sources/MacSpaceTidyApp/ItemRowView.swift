import AppKit
import MacSpaceTidyCore
import SwiftUI

struct ItemRowView: View {
    private static let SIZE_BAR_WIDTH: CGFloat = 80
    private static let SIZE_TEXT_WIDTH: CGFloat = 80

    let model: AppModel
    let item: ScanItem
    let largestBytes: Int64

    @State private var isMoveBackAsked = false
    @State private var isManualMoveAsked = false

    var body: some View {
        let isSelectable = PlanSelection.isSelectable(item)
        HStack(spacing: 10) {
            CheckboxView(state: model.plan.isSelected(item) ? .on : .off, isEnabled: isSelectable) {
                model.plan.toggle(item)
            }
            .help(isSelectable ? "" : disabledReason)
            .padding(.leading, 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.needsAdmin {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Needs your admin password. Always deleted now.")
                    }
                    RiskBadgeView(risk: item.risk)
                }
                Text(item.linkTarget.map { "→ \($0)" } ?? item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let lastChange = lastChangeText {
                    Text(lastChange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if PlanSelection.isRecentlyUsed(item), let changed = item.size.newestChange {
                    Label("Changed \(RelativeTime.ago(changed)), so it is not checked. The app may be using it.", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let cachedAt = item.size.cachedAt {
                    Label("Size from the last scan, \(RelativeTime.ago(cachedAt)). Counting again…", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.canMove {
                movePicker
            }
            if item.action == .moveBack {
                Button("Move back") { isMoveBackAsked = true }
                    .controlSize(.small)
            }
            sizeBar
            Text(sizeText)
                .monospacedDigit()
                .foregroundStyle(isOldNumber || item.category == .alreadyMoved && item.size.bytes == 0 ? .secondary : .primary)
                .help(item.size.cachedAt.map { "Measured \(RelativeTime.ago($0)). A new count is running." } ?? "")
                .frame(width: ItemRowView.SIZE_TEXT_WIDTH, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contextMenu {
            if item.path.hasPrefix("/") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.linkTarget ?? item.path)])
                }
            }
            if item.offersManualMove {
                Button("Move to External Disk…") {
                    model.refreshDiskChoices()
                    isManualMoveAsked = true
                }
            }
        }
        .alert("Move \(item.title) back to this Mac?", isPresented: $isMoveBackAsked) {
            Button("Move Back") { model.runSingle(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder is copied back and checked, then the link is replaced. The copy on the external disk stays; delete it yourself when you are sure.")
        }
        .alert("Move \(item.title) to the external disk?", isPresented: $isManualMoveAsked) {
            Button("Move", role: .destructive) { model.runSingle(item.with(action: .move)) }
                .disabled(model.usableDiskRoot == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(manualMoveMessage)
        }
    }

    private var sizeBar: some View {
        let fraction = CGFloat(item.size.bytes) / CGFloat(max(largestBytes, 1))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule().fill(CategoryColors.color(item.category)).frame(width: ItemRowView.SIZE_BAR_WIDTH * fraction)
        }
        .frame(width: ItemRowView.SIZE_BAR_WIDTH, height: 6)
    }

    /// "Move | Delete" for caches that may be moved instead. Needs a chosen disk.
    @ViewBuilder
    private var movePicker: some View {
        if model.usableDiskRoot == nil {
            Text("Can be moved")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Choose an external disk in Settings (Cmd-,) to move this cache instead of deleting it.")
        } else {
            Picker("", selection: Binding(
                get: { model.effectiveAction(item) == .move },
                set: { model.plan.setMove(item, $0) }
            )) {
                Text("Move").tag(true)
                Text("Delete").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Move keeps the cache on the external disk. Delete removes it; the tool downloads it again when needed.")
        }
    }

    /// Shown for moved folders: an old date means the folder may be safe to clean.
    private var lastChangeText: String? {
        guard item.category == .alreadyMoved || item.category == .external, let date = item.size.newestChange else {
            return nil
        }
        return "Last changed \(RelativeTime.ago(date))"
    }

    private var sizeText: String {
        if item.category == .alreadyMoved && item.size.bytes == 0 {
            return model.isScanningExternal ? "measuring…" : "external"
        }
        if item.size.isIncomplete && item.size.bytes == 0 {
            return "no access"
        }
        return (isOldNumber ? "~ " : "") + ByteText.format(item.size.bytes)
    }

    /// The number comes from an earlier scan and a new count is running.
    private var isOldNumber: Bool {
        return item.size.cachedAt != nil
    }

    private var manualMoveMessage: String {
        guard model.usableDiskRoot != nil else {
            return "Choose an external disk in Settings (Cmd-,) first."
        }
        let warning = item.category == .largeUnknown
            ? "This folder is not in the catalog, so nobody checked that its app works from an external disk. "
                + "The link breaks when the disk is not connected."
            : "This is a cache. Some apps delete and recreate their cache folder, and that removes the link. "
                + "The link also breaks when the disk is not connected."
        if let refusal = model.moveRefusal(item.with(action: .move)) {
            return warning + "\n\nIt cannot be moved now: \(refusal)"
        }
        return warning
    }

    private var disabledReason: String {
        switch item.action {
        case .cleanInApp: return "Clean this inside the app."
        case .info: return item.offersManualMove ? "Information only. Right-click to move it by hand." : "Information only."
        case .delete, .deleteSimulatorRuntime, .move, .moveBack, .cleanExternal, .deleteExternalCopy, .never: return ""
        }
    }
}
