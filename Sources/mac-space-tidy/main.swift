import Foundation
import MacSpaceTidyCore

private let USAGE = """
Usage: mac-space-tidy               Full-screen interface: scan, check items, optimize.
       mac-space-tidy scan [--all] [--moved-sizes]

  scan            Read-only report: disk use, problems, and what is safe to clean or move.
  --all           Show every item, not only the biggest ones in each category.
  --moved-sizes   Also measure folders already on an external disk (slow).
"""

private let ITEMS_PER_CATEGORY = 10
private let ACTION_COLUMN_WIDTH = 7
private let SIZE_COLUMN_WIDTH = 9

private let ACTION_LABELS: [ItemAction: String] = [
    .delete: "delete",
    .move: "move",
    .deleteSimulatorRuntime: "delete",
    .cleanInApp: "in app",
    .moveBack: "moved",
    .cleanExternal: "clean",
    .deleteExternalCopy: "delete",
    .info: "info",
]

private let DEFAULT_TERMINAL_WIDTH = 80
private let PROGRESS_PREFIX = "Scanning "

private func terminalWidth() -> Int {
    var size = winsize()
    guard ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else {
        return DEFAULT_TERMINAL_WIDTH
    }
    return Int(size.ws_col)
}

/// One line that the next update overwrites. Longer text would wrap and leave lines behind.
private func showProgress(_ step: String) {
    let line = String((PROGRESS_PREFIX + step).prefix(terminalWidth() - 1))
    FileHandle.standardError.write(Data("\u{1B}[2K\r\(line)".utf8))
}

private func formatBytes(_ bytes: Int64) -> String {
    return ByteText.format(bytes)
}

private func padLeft(_ text: String, _ width: Int) -> String {
    return String(repeating: " ", count: max(0, width - text.count)) + text
}

private func sizeLabel(_ item: ScanItem, measuresMovedItems: Bool) -> String {
    if item.category == .alreadyMoved && !measuresMovedItems {
        return "external"
    }
    if item.size.isIncomplete && item.size.bytes == 0 {
        return "no access"
    }
    return formatBytes(item.size.bytes)
}

private func printReport(_ report: ScanReport, showsAll: Bool, measuresMovedItems: Bool) {
    let disk = report.disk
    let usedPercent = Int(Double(disk.usedBytes) / Double(max(disk.totalBytes, 1)) * 100)
    print("Disk: \(formatBytes(disk.usedBytes)) used of \(formatBytes(disk.totalBytes)) (\(usedPercent)%), \(formatBytes(disk.freeBytes)) free")
    if report.hasUnreadableFolders {
        print("Some folders could not be read. Give Full Disk Access to your terminal for full numbers.")
    }

    print("\nProblems: \(report.problems.isEmpty ? "none" : String(report.problems.count))")
    for problem in report.problems {
        print("  ! \(problem.path ?? "disk"): \(problem.detail)")
    }

    for category in ItemCategory.allCases {
        let items = report.items(in: category)
        guard category != .system, !items.isEmpty else {
            continue
        }
        let total = category == .alreadyMoved && !measuresMovedItems ? "\(items.count) folders" : formatBytes(report.totalBytes(in: category))
        print("\n\(category.title) — \(total)")
        let shownItems = showsAll ? items : Array(items.prefix(ITEMS_PER_CATEGORY))
        for item in shownItems {
            let checkbox = item.checkedByDefault ? "[x]" : "[ ]"
            let action = ACTION_LABELS[item.action] ?? ""
            let admin = item.needsAdmin ? " (admin)" : ""
            let target = item.linkTarget.map { " → \($0)" } ?? ""
            let size = padLeft(sizeLabel(item, measuresMovedItems: measuresMovedItems), SIZE_COLUMN_WIDTH)
            let actionColumn = action.padding(toLength: ACTION_COLUMN_WIDTH, withPad: " ", startingAt: 0)
            print("  \(checkbox) \(size)  \(actionColumn) \(item.title)\(admin)\(target)")
        }
        let hiddenItems = items.dropFirst(shownItems.count)
        if !hiddenItems.isEmpty {
            let hiddenBytes = hiddenItems.reduce(0) { $0 + $1.size.bytes }
            let hiddenSize = category == .alreadyMoved && !measuresMovedItems ? "" : ", \(formatBytes(hiddenBytes))"
            print("      … \(hiddenItems.count) more\(hiddenSize) (use --all)")
        }
    }

    let safeBytes = report.items.filter { $0.checkedByDefault }.reduce(0) { $0 + $1.size.bytes }
    print("\nChecked by default (safe): \(formatBytes(safeBytes)). Freed space is measured with df after the action.")
}

private func runScan(showsAll: Bool, measuresMovedItems: Bool) -> Int32 {
    var options = ScanOptions.standard()
    options.measuresMovedItems = measuresMovedItems
    do {
        let catalog = try Catalog.loadBundled()
        var report = try Scanner.scan(catalog: catalog, options: options) { step in
            showProgress(step)
        }
        if measuresMovedItems {
            report = ExternalScanner.scan(report: report, catalog: catalog, options: options) { step in
                showProgress(step)
            }
        }
        FileHandle.standardError.write(Data("\u{1B}[2K\r".utf8))
        printReport(report, showsAll: showsAll, measuresMovedItems: measuresMovedItems)
        return 0
    } catch {
        FileHandle.standardError.write(Data("Scan failed: \(error)\n".utf8))
        return 1
    }
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case nil where Terminal.isInteractive:
    do {
        TuiApp(catalog: try Catalog.loadBundled()).run()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("The rules catalog could not be loaded: \(error)\n".utf8))
        exit(1)
    }
case "scan", nil:
    let flags = Set(arguments.dropFirst())
    let knownFlags: Set<String> = ["--all", "--moved-sizes"]
    guard flags.isSubset(of: knownFlags) else {
        print(USAGE)
        exit(2)
    }
    exit(runScan(showsAll: flags.contains("--all"), measuresMovedItems: flags.contains("--moved-sizes")))
default:
    print(USAGE)
    exit(2)
}
