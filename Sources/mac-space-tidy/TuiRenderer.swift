import Foundation
import MacSpaceTidyCore

/// Drawing of the three screens. Plain text is fitted first; colors wrap fitted text, so widths stay right.
extension TuiApp {
    private typealias T = TuiText

    private static let ITEM_PREFIX_WIDTH = 21
    private static let SIZE_WIDTH = 10
    private static let CATEGORY_PREFIX_WIDTH = 9
    private static let MAIN_KEYS = "↑↓ move  space check  enter open  m move/delete  b back  i ignore  x fix  d disk  s scan  o optimize  q quit"
    private static let CONFIRM_KEYS = "enter run  t Trash/Delete now  d disk  ↑↓ scroll  esc back"

    func render(width: Int, height: Int) -> [String] {
        switch screen {
        case .main: return renderMain(width: width, height: height)
        case .confirm: return renderConfirm(width: width, height: height)
        case .progress: return renderProgress(width: width)
        }
    }

    // MARK: Main

    private func renderMain(width: Int, height: Int) -> [String] {
        var lines = [T.BOLD + T.fit(" MacSpaceTidy", width) + T.RESET, ""]
        if let report = snapshot.report {
            lines += diskLines(report, width: width)
        }
        if snapshot.isScanning {
            lines.append(T.fit("  Scanning \(snapshot.scanStep)", width))
        } else if snapshot.isScanningExternal {
            lines.append(T.YELLOW + T.fit("  Counting folders on external disks again. Sizes marked ~ are from the last scan.", width) + T.RESET)
        }
        if let report = snapshot.report {
            if let lowSpace = report.problems.first(where: { $0.kind == .lowFreeSpace }) {
                lines.append(T.RED + T.fit("  ! \(lowSpace.detail)", width) + T.RESET)
            }
            if report.hasUnreadableFolders {
                lines.append(T.YELLOW + T.fit("  Some folders could not be read. Give Full Disk Access to your terminal for full numbers.", width) + T.RESET)
            }
        }
        lines.append(T.DIM + String(repeating: "─", count: width) + T.RESET)
        headerLineCount = lines.count

        let rows = rows()
        let visible = max(height - lines.count - TuiApp.FOOTER_LINES, TuiApp.MIN_LIST_LINES)
        cursor = min(cursor, max(rows.count - 1, 0))
        if cursor < listScroll {
            listScroll = cursor
        } else if cursor >= listScroll + visible {
            listScroll = cursor - visible + 1
        }
        for index in listScroll..<min(listScroll + visible, rows.count) {
            lines.append(rowLine(rows[index], width: width, isCurrent: index == cursor))
        }
        if rows.isEmpty && !snapshot.isScanning {
            lines.append("  Press s to scan.")
        }
        while lines.count < height - TuiApp.FOOTER_LINES {
            lines.append("")
        }
        let current = rows.indices.contains(cursor) ? rows[cursor] : nil
        lines += footer(description: description(of: current), keys: TuiApp.MAIN_KEYS, width: width)
        return lines
    }

    private func diskLines(_ report: ScanReport, width: Int) -> [String] {
        let disk = report.disk
        var lines = [T.fit("  This Mac: \(ByteText.format(disk.usedBytes)) used of \(ByteText.format(disk.totalBytes)), \(ByteText.format(disk.freeBytes)) free", width)]
        var segments: [(title: String, bytes: Int64, color: Int)] = []
        var knownBytes: Int64 = 0
        for category in ItemCategory.allCases where category.isOnInternalDisk {
            let bytes = report.internalBytes(in: category)
            if bytes > 0 {
                knownBytes += bytes
                segments.append((category.title, bytes, T.colorCode(category)))
            }
        }
        segments.append(("macOS, apps, your files", max(disk.usedBytes - knownBytes, 0), T.otherColor))
        lines.append("  " + bar(segments.map { ($0.bytes, $0.color) }, total: disk.totalBytes, width: width - 4))
        lines += legend(segments, width: width)
        for external in report.externalDisks {
            let other = max(external.space.usedBytes - external.movedBytes, 0)
            let text = "  \(external.name): \(ByteText.format(external.space.usedBytes)) used of \(ByteText.format(external.space.totalBytes)), "
                + "\(ByteText.format(external.space.freeBytes)) free, moved from this Mac: \(ByteText.format(external.movedBytes))"
            lines.append(T.fit(text, width))
            lines.append("  " + bar([(external.movedBytes, T.colorCode(.alreadyMoved)), (other, T.otherColor)], total: external.space.totalBytes, width: width - 4))
        }
        return lines
    }

    private func bar(_ segments: [(bytes: Int64, color: Int)], total: Int64, width: Int) -> String {
        var text = ""
        var usedCells = 0
        for segment in segments {
            let cells = Int((Double(segment.bytes) / Double(max(total, 1)) * Double(width)).rounded())
            let fitted = min(cells, width - usedCells)
            text += T.background(segment.color) + String(repeating: " ", count: max(fitted, 0))
            usedCells += max(fitted, 0)
        }
        return text + T.background(T.freeColor) + String(repeating: " ", count: max(width - usedCells, 0)) + T.RESET
    }

    private func legend(_ segments: [(title: String, bytes: Int64, color: Int)], width: Int) -> [String] {
        var lines: [String] = []
        var line = "  "
        var lineWidth = 2
        for segment in segments {
            let plain = "■ \(segment.title) \(ByteText.format(segment.bytes))   "
            if lineWidth + plain.count > width && lineWidth > 2 {
                lines.append(line)
                line = "  "
                lineWidth = 2
            }
            line += T.foreground(segment.color) + "■" + T.RESET + " \(segment.title) " + T.DIM + ByteText.format(segment.bytes) + T.RESET + "   "
            lineWidth += plain.count
        }
        lines.append(line)
        return lines
    }

    private func rowLine(_ row: TuiRow, width: Int, isCurrent: Bool) -> String {
        switch row {
        case .problem(let problem):
            let path = problem.path.map { PathTools.abbreviate($0, home: options.home) } ?? "disk"
            let text = T.fit(" ! \(T.fitMiddle(path, width / 2))  \(problem.detail)", width)
            return (isCurrent ? T.INVERSE : T.YELLOW) + text + T.RESET
        case .category(let category, let items):
            let arrow = expanded.contains(category) ? "▾" : "▸"
            let totalBytes = items.reduce(0) { $0 + $1.size.bytes }
            let isOldNumber = snapshot.isScanningExternal && items.contains { $0.size.cachedAt != nil }
            let isMeasuring = snapshot.isScanningExternal && totalBytes == 0 && (category == .alreadyMoved || category == .external)
            let total = isMeasuring ? "measuring…" : (isOldNumber ? "~ " : "") + ByteText.format(totalBytes)
            let right = " \(items.count) items  " + T.padLeft(total, TuiApp.SIZE_WIDTH)
            let title = T.fit(category.title, width - TuiApp.CATEGORY_PREFIX_WIDTH - right.count)
            let prefix = " \(arrow) \(checkbox(for: items)) "
            if isCurrent {
                return T.INVERSE + prefix + "■ " + T.BOLD + title + right + T.RESET
            }
            return prefix + T.foreground(T.colorCode(category)) + "■" + T.RESET + " " + T.BOLD + title + T.RESET + T.DIM + right + T.RESET
        case .item(let item):
            let mark: String
            if item.action == .moveBack {
                mark = " ↩ "
            } else if PlanSelection.isSelectable(item) {
                mark = plan.isSelected(item) ? "[x]" : "[ ]"
            } else {
                mark = "   "
            }
            let suffix = itemSuffix(item)
            let titleWidth = width - TuiApp.ITEM_PREFIX_WIDTH - suffix.count
            let text = "     \(mark) " + T.padLeft(sizeText(item), TuiApp.SIZE_WIDTH) + "  " + T.fitMiddle(item.title, titleWidth)
            let padded = T.fit(text + suffix, width)
            return isCurrent ? T.INVERSE + padded + T.RESET : padded
        }
    }

    private func checkbox(for items: [ScanItem]) -> String {
        let selectable = items.filter(PlanSelection.isSelectable)
        guard !selectable.isEmpty else {
            return "   "
        }
        let selected = selectable.filter(plan.isSelected).count
        return selected == 0 ? "[ ]" : (selected == selectable.count ? "[x]" : "[-]")
    }

    private func itemSuffix(_ item: ScanItem) -> String {
        var suffix = ""
        if item.canMove {
            if plan.effectiveAction(item) != .move {
                suffix += "  [Delete]"
            } else {
                suffix += usableDiskRoot == nil ? "  [Move: no disk, skipped]" : "  [Move]"
            }
        } else if item.offersManualMove && usableDiskRoot != nil {
            suffix += "  (m: move by hand)"
        }
        if item.needsAdmin {
            suffix += "  (admin)"
        }
        if item.risk != .low {
            suffix += item.risk == .medium ? "  ! medium risk" : "  ! high risk"
        }
        if let target = item.linkTarget {
            suffix += "  → " + T.fitMiddle(target, 40)
        }
        return suffix
    }

    private func sizeText(_ item: ScanItem) -> String {
        if item.category == .alreadyMoved && item.size.bytes == 0 {
            return snapshot.isScanningExternal ? "measuring" : "external"
        }
        if item.size.isIncomplete && item.size.bytes == 0 {
            return "no access"
        }
        return (item.size.cachedAt != nil ? "~" : "") + ByteText.format(item.size.bytes)
    }

    private func description(of row: TuiRow?) -> String {
        switch row {
        case .problem(let problem):
            return problem.kind == .diskNotMounted ? problem.detail : "\(problem.detail) Press x to fix."
        case .category(let category, let items):
            return "\(category.title): \(items.count) items. Space checks all, Enter opens."
        case .item(let item):
            var text = item.reason
            if let date = item.size.newestChange, item.category == .alreadyMoved || item.category == .external {
                text += " Last changed \(RelativeTime.ago(date))."
            }
            if PlanSelection.isRecentlyUsed(item), let changed = item.size.newestChange {
                text = "Changed \(RelativeTime.ago(changed)), so it is not checked. The app may be using it. " + text
            }
            if let cachedAt = item.size.cachedAt {
                text = "Size from the last scan, \(RelativeTime.ago(cachedAt)). Counting again… " + text
            }
            return text
        case nil:
            return ""
        }
    }

    private func footer(description: String, keys: String, width: Int) -> [String] {
        let middle: String
        if let question {
            middle = T.BOLD + T.YELLOW + T.fit(" " + question.text, width) + T.RESET
        } else if let message {
            middle = T.YELLOW + T.fit(" " + message, width) + T.RESET
        } else {
            middle = T.DIM + T.fit(" " + description, width) + T.RESET
        }
        let selectedBytes = chosenItems.reduce(0) { $0 + $1.size.bytes }
        let total = screen == .main ? "  Checked: \(ByteText.format(selectedBytes))" : ""
        return [
            T.DIM + String(repeating: "─", count: width) + T.RESET,
            middle,
            T.DIM + T.fit(" " + keys, width - total.count) + T.RESET + T.BOLD + total + T.RESET,
        ]
    }

    // MARK: Confirm

    private func renderConfirm(width: Int, height: Int) -> [String] {
        let items = chosenItems
        let moves = items.filter { $0.action == .move }
        let externals = items.filter { $0.category == .external }
        let trashed = items.filter { $0.action == .trashOnly }
        let cleans = items.filter { $0.action != .move && $0.action != .trashOnly && $0.category != .external }
        // Running apps first: a long list must not hide them.
        var body = runningApps.map { T.YELLOW + T.fit("\($0) is running. Its items are skipped unless you quit it.", width) + T.RESET }
        if !body.isEmpty {
            body.append("")
        }
        if !moves.isEmpty {
            if usableDiskRoot == nil {
                body.append(T.BOLD + T.YELLOW + T.fit("SKIPPED, no external disk — \(moves.count) folders, \(ByteText.format(total(moves))) stay on this Mac", width) + T.RESET)
                body.append(T.DIM + T.fit("Nothing is deleted instead. To free this space: press d to choose a disk, or m on an item to delete it.", width) + T.RESET)
            } else {
                body.append(T.BOLD + T.BLUE + T.fit("MOVE to external disk — \(moves.count) folders, \(ByteText.format(total(moves)))", width) + T.RESET)
                body.append(T.DIM + T.fit("Nothing is lost: each folder is copied, checked, and replaced with a link. The link breaks when the disk is not connected.", width) + T.RESET)
            }
            if let disk = diskChoices.first(where: { $0.path == usableDiskRoot }) {
                body.append(T.fit("  Disk: \(disk.name), \(ByteText.format(disk.freeBytes)) free, \(disk.fileSystem)   (d: change)", width))
            } else {
                body.append(T.YELLOW + T.fit("  No disk chosen. These items are skipped.", width) + T.RESET)
            }
            for item in moves {
                body.append(itemLine(item, width: width))
                let refusal = usableDiskRoot.flatMap { Mover(catalog: catalog, options: options).moveRefusal(item, diskRoot: $0) }
                if let refusal {
                    body.append(T.YELLOW + T.fit("      \(refusal)", width) + T.RESET)
                } else if let root = usableDiskRoot {
                    body.append(T.DIM + T.fit("      → \(Mover.destination(for: item.path, diskRoot: root))", width) + T.RESET)
                }
            }
            body.append("")
        }
        if !trashed.isEmpty {
            body.append(T.BOLD + T.YELLOW + T.fit("TO THE TRASH — \(trashed.count) items, \(ByteText.format(total(trashed)))", width) + T.RESET)
            body.append(T.DIM + T.fit("These are your own files or data of removed apps. They always go to the Trash, so you can put them back.", width) + T.RESET)
            body += trashed.map { itemLine($0, width: width) }
            body.append("")
        }
        if !cleans.isEmpty {
            let howText = deleteMode == .trash
                ? "What is inside each folder goes to the Trash; the folders stay. The space is freed after you empty the Trash."
                : "What is inside each folder is deleted for good; the folders stay. These are caches that apps rebuild."
            body.append(T.BOLD + T.RED + T.fit("CLEAN — \(cleans.count) items, \(ByteText.format(total(cleans)))", width) + T.RESET)
            body.append(T.DIM + T.fit(howText, width) + T.RESET)
            body.append(T.fit("  How: " + (deleteMode == .trash ? "[Move to Trash]  Delete now" : " Move to Trash  [Delete now]") + "   (t: switch)", width))
            if cleans.contains(where: \.needsAdmin) {
                body.append(T.DIM + T.fit("  (admin) items ask for your password and are always deleted now.", width) + T.RESET)
            }
            body += cleans.map { itemLine($0, width: width) }
            body.append("")
        }
        if !externals.isEmpty {
            body.append(T.BOLD + T.MAGENTA + T.fit("CLEAN ON EXTERNAL DISK — \(externals.count) items, \(ByteText.format(total(externals)))", width) + T.RESET)
            body.append(T.DIM + T.fit("Frees the external disk, not this Mac. Caches are emptied; folders and links stay.", width) + T.RESET)
            body += externals.map { itemLine($0, width: width) }
            body.append("")
        }
        var lines = [T.BOLD + T.fit(" Check what will happen", width) + T.RESET, ""]
        let visible = max(height - lines.count - TuiApp.FOOTER_LINES, TuiApp.MIN_LIST_LINES)
        confirmScroll = min(confirmScroll, max(body.count - visible, 0))
        lines += body.dropFirst(confirmScroll).prefix(visible).map { "  " + $0 }
        while lines.count < height - TuiApp.FOOTER_LINES {
            lines.append("")
        }
        lines += footer(description: "Nothing changes until you press Enter.", keys: TuiApp.CONFIRM_KEYS, width: width)
        return lines
    }

    private func itemLine(_ item: ScanItem, width: Int) -> String {
        let size = T.padLeft(ByteText.format(item.size.bytes), TuiApp.SIZE_WIDTH)
        let admin = item.needsAdmin ? " (admin)" : ""
        return T.fit("  " + size + "  " + T.fitMiddle(item.title, width - TuiApp.SIZE_WIDTH - 8 - admin.count) + admin, width - 2)
    }

    private func total(_ items: [ScanItem]) -> Int64 {
        return items.reduce(0) { $0 + $1.size.bytes }
    }

    // MARK: Progress and result

    private func renderProgress(width: Int) -> [String] {
        guard let result = snapshot.result else {
            let done = snapshot.optimizeIndex
            return [
                T.BOLD + T.fit(" Working… \(min(done + 1, progressTotal)) of \(progressTotal)", width) + T.RESET,
                "",
                "  " + bar([(Int64(done), T.colorCode(.caches))], total: Int64(max(progressTotal, 1)), width: width - 4),
                T.fit("  \(snapshot.optimizeStep)", width),
                "",
                T.YELLOW + T.fit("  " + (message ?? ""), width) + T.RESET,
                T.DIM + T.fit("  esc: stop after the current item. A move is never cut in the middle.", width) + T.RESET,
            ]
        }
        var lines = [
            T.BOLD + T.GREEN + T.fit(" Freed \(ByteText.format(max(result.freedBytes, 0)))", width) + T.RESET,
            T.DIM + T.fit("  Measured on the disk before and after. Now \(ByteText.format(result.diskAfter.freeBytes)) free.", width) + T.RESET,
            "",
        ]
        if result.wasCancelled {
            lines.append(T.fit("  Stopped. The rest was not touched.", width))
        }
        if deleteMode == .trash && result.outcomes.contains(where: { $0.status == .done && $0.item.action == .delete }) {
            lines.append(T.fit("  Empty the Trash to free the space of trashed files.", width))
        }
        for outcome in result.outcomes where outcome.status == .done && outcome.item.action == .moveBack {
            lines.append(T.fit("  The copy on the external disk stays at \(outcome.item.linkTarget ?? "?"). Delete it when you are sure.", width))
        }
        let noDisk = result.outcomes.filter { $0.status == .skipped(Optimizer.NO_DISK_REASON) }
        if !noDisk.isEmpty {
            let bytes = noDisk.reduce(0) { $0 + $1.item.size.bytes }
            lines.append(T.YELLOW + T.fit("  \(noDisk.count) moves skipped (\(ByteText.format(bytes))): no external disk. Press d to choose one, then optimize again.", width) + T.RESET)
        }
        let notDone = result.outcomes.filter { $0.status != .done }
        if !notDone.isEmpty {
            lines.append("")
            lines.append(T.BOLD + T.fit("  Not done: \(notDone.count)", width) + T.RESET)
            for outcome in notDone.prefix(max(terminal.height - lines.count - 3, 1)) {
                let reason: String
                switch outcome.status {
                case .skipped(let text): reason = "skipped: \(text)"
                case .failed(let text): reason = "failed: \(text)"
                case .done: reason = ""
                }
                lines.append(T.fit("    \(outcome.item.title) — \(reason)", width))
            }
        }
        lines.append("")
        lines.append(T.DIM + T.fit("  enter: scan again", width) + T.RESET)
        return lines
    }
}
