import Foundation
import MacSpaceTidyCore

private let USAGE = """
Usage: mac-space-tidy               Full-screen interface: scan, check items, optimize.
       mac-space-tidy scan [--all] [--moved-sizes] [--json]
       mac-space-tidy history [--all] [--json]

  scan            Read-only report: disk use, problems, and what is safe to clean or move.
  --all           Show every item, not only the biggest ones (scan), or the whole log (history).
  --moved-sizes   Also measure folders already on an external disk (slow).
  --json          Print JSON instead of text, for scripts.
  history         What was moved, trashed, or deleted, newest last. The last \(HISTORY_LINES) entries unless --all.
"""

private let HISTORY_LINES = 50

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
    .trashOnly: "trash",
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

private struct JsonItem: Encodable {
    let path: String
    let title: String
    let category: ItemCategory
    let action: ItemAction
    let risk: Risk
    let bytes: Int64
    let isIncomplete: Bool
    let checkedByDefault: Bool
    let needsAdmin: Bool
    let linkTarget: String?
    let reason: String
}

private struct JsonProblem: Encodable {
    let kind: String
    let path: String?
    let detail: String
}

private struct JsonReport: Encodable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let problems: [JsonProblem]
    let items: [JsonItem]
}

private func jsonText(_ value: some Encodable, dates: Bool = false) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if dates {
        encoder.dateEncodingStrategy = .iso8601
    }
    return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

private func printJson(_ report: ScanReport) {
    let items = report.items.filter { $0.category != .system }.map { item in
        JsonItem(
            path: item.path, title: item.title, category: item.category, action: item.action, risk: item.risk, bytes: item.size.bytes,
            isIncomplete: item.size.isIncomplete, checkedByDefault: item.checkedByDefault, needsAdmin: item.needsAdmin,
            linkTarget: item.linkTarget, reason: item.reason
        )
    }
    let problems = report.problems.map { JsonProblem(kind: $0.kind.rawValue, path: $0.path, detail: $0.detail) }
    print(jsonText(JsonReport(
        totalBytes: report.disk.totalBytes, usedBytes: report.disk.usedBytes, freeBytes: report.disk.freeBytes, problems: problems, items: items
    )))
}

private struct HistoryRow: Encodable {
    let date: Date
    let action: String
    let path: String
    let bytes: Int64?
    let result: String
}

private func historyRows() -> [HistoryRow] {
    let options = ScanOptions.standard()
    let cleans = CleanLog.read(from: options.cleanLogPath).map {
        HistoryRow(date: $0.date, action: $0.action, path: $0.path, bytes: $0.bytes, result: $0.result)
    }
    let moves = MoveJournal.read(from: options.journalPath).map { record in
        let isMove = record.kind == MoveJournal.KIND_MOVE
        return HistoryRow(date: record.date, action: isMove ? "move" : "move back", path: isMove ? record.source : record.destination, bytes: nil, result: "done")
    }
    return (cleans + moves).sorted { $0.date < $1.date }
}

private func runHistory(showsAll: Bool, asJson: Bool) -> Int32 {
    let rows = historyRows()
    let shown = showsAll ? rows : Array(rows.suffix(HISTORY_LINES))
    if asJson {
        print(jsonText(shown, dates: true))
        return 0
    }
    if shown.isEmpty {
        print("Nothing was cleaned or moved yet.")
        return 0
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    for row in shown {
        let size = padLeft(row.bytes.map(formatBytes) ?? "", SIZE_COLUMN_WIDTH)
        let result = row.result == "done" ? "" : "  (\(row.result))"
        let action = row.action.padding(toLength: 9, withPad: " ", startingAt: 0)
        print("\(formatter.string(from: row.date))  \(action) \(size)  \(PathTools.abbreviate(row.path, home: NSHomeDirectory()))\(result)")
    }
    return 0
}

private func runScan(showsAll: Bool, measuresMovedItems: Bool, asJson: Bool) -> Int32 {
    var options = ScanOptions.standard()
    options.measuresMovedItems = measuresMovedItems
    do {
        let catalog = try Catalog.loadBundled()
        // Progress text goes to stderr; JSON output stays clean for a pipe.
        let progress: MacSpaceTidyCore.Scanner.Progress = { step in
            if !asJson {
                showProgress(step)
            }
        }
        var report = try Scanner.scan(catalog: catalog, options: options, progress: progress)
        if measuresMovedItems {
            report = ExternalScanner.scan(report: report, catalog: catalog, options: options, progress: progress)
        }
        if asJson {
            printJson(report)
            return 0
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
    let knownFlags: Set<String> = ["--all", "--moved-sizes", "--json"]
    guard flags.isSubset(of: knownFlags) else {
        print(USAGE)
        exit(2)
    }
    exit(runScan(showsAll: flags.contains("--all"), measuresMovedItems: flags.contains("--moved-sizes"), asJson: flags.contains("--json")))
case "history":
    let flags = Set(arguments.dropFirst())
    guard flags.isSubset(of: ["--all", "--json"]) else {
        print(USAGE)
        exit(2)
    }
    exit(runHistory(showsAll: flags.contains("--all"), asJson: flags.contains("--json")))
default:
    print(USAGE)
    exit(2)
}
