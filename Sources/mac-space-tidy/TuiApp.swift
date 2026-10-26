import Foundation
import MacSpaceTidyCore

/// Full-screen terminal interface. Same flow as the app: Scan, check items, Optimize.
@MainActor
final class TuiApp {
    enum Screen {
        case main
        case confirm
        case progress
    }

    /// A yes/no question shown in the footer.
    struct Question {
        let text: String
        let action: @MainActor () -> Void
    }

    static let FOOTER_LINES = 3
    static let MIN_LIST_LINES = 3
    private static let FRAME_MILLISECONDS: Int32 = 120

    let terminal = Terminal()
    let background = TuiBackground()
    let catalog: Catalog
    let options = ScanOptions.standard()

    var screen = Screen.main
    var snapshot = TuiBackground.Snapshot()
    var plan = PlanSelection()
    var expanded: Set<ItemCategory> = []
    var cursor = 0
    var listScroll = 0
    var confirmScroll = 0
    var deleteMode = SharedSettings.deleteMode
    var diskRoot = SharedSettings.moveDiskRoot
    var diskChoices: [DiskChoice] = []
    var runningApps: [String] = []
    var question: Question?
    var message: String?
    var progressTotal = 0
    /// Lines above the list on the main screen. Set while drawing, used for paging.
    var headerLineCount = 0
    private var seenScanVersion = 0
    private var isRunning = true

    init(catalog: Catalog) {
        self.catalog = catalog
    }

    var usableDiskRoot: String? {
        guard let diskRoot, diskChoices.contains(where: { $0.path == diskRoot && $0.problem == nil }) else {
            return nil
        }
        return diskRoot
    }

    var chosenItems: [ScanItem] {
        return plan.chosenItems(from: snapshot.report?.items ?? [])
    }

    func run() {
        terminal.enter()
        defer { terminal.leave() }
        refreshDiskChoices()
        startScan()
        while isRunning {
            syncFromBackground()
            terminal.draw(render(width: terminal.width, height: terminal.height))
            if let key = terminal.readKey(timeoutMilliseconds: TuiApp.FRAME_MILLISECONDS) {
                message = nil
                handle(key)
            }
        }
    }

    // MARK: Rows

    func rows() -> [TuiRow] {
        guard let report = snapshot.report else {
            return []
        }
        var rows = report.problems.filter { $0.kind != .lowFreeSpace }.map(TuiRow.problem)
        for category in ItemCategory.allCases where category != .system {
            let items = report.items(in: category)
            if items.isEmpty {
                continue
            }
            rows.append(.category(category, items))
            if expanded.contains(category) {
                rows += items.map(TuiRow.item)
            }
        }
        return rows
    }

    // MARK: Keys

    private func handle(_ key: Terminal.Key) {
        if let question {
            if key == .character("y") {
                self.question = nil
                question.action()
            } else if key == .character("n") || key == .escape {
                self.question = nil
            }
            return
        }
        if key == .interrupt {
            isRunning = false
            return
        }
        switch screen {
        case .main: handleMain(key)
        case .confirm: handleConfirm(key)
        case .progress: handleProgress(key)
        }
    }

    private func handleMain(_ key: Terminal.Key) {
        let rows = rows()
        cursor = min(cursor, max(rows.count - 1, 0))
        let current = rows.indices.contains(cursor) ? rows[cursor] : nil
        switch key {
        case .up, .character("k"): cursor = max(cursor - 1, 0)
        case .down, .character("j"): cursor = min(cursor + 1, max(rows.count - 1, 0))
        case .pageUp: cursor = max(cursor - listHeight(), 0)
        case .pageDown: cursor = min(cursor + listHeight(), max(rows.count - 1, 0))
        case .space: toggle(current)
        case .enter, .right, .left: expandOrCollapse(current, key: key, rows: rows)
        case .character("m"): switchMoveOrDelete(current)
        case .character("b"): askMoveBack(current)
        case .character("i"): askIgnore(current)
        case .character("x"): askFix(current)
        case .character("d"): nextDisk()
        case .character("s"): startScan()
        case .character("o"): openConfirm()
        case .character("q"), .escape: isRunning = false
        default: break
        }
    }

    private func handleConfirm(_ key: Terminal.Key) {
        switch key {
        case .up, .character("k"): confirmScroll = max(confirmScroll - 1, 0)
        case .down, .character("j"): confirmScroll += 1
        case .character("d"): nextDisk()
        case .character("t"):
            deleteMode = deleteMode == .trash ? .deleteNow : .trash
            SharedSettings.deleteMode = deleteMode
        case .enter: startOptimize(chosenItems)
        case .escape, .character("q"): screen = .main
        default: break
        }
    }

    private func handleProgress(_ key: Terminal.Key) {
        if snapshot.result != nil {
            if key == .enter || key == .escape || key == .character("q") {
                background.modify { $0.result = nil }
                screen = .main
                startScan()
            }
        } else if key == .escape {
            background.modify { $0.isCancelRequested = true }
            message = "Stopping after the current item…"
        }
    }

    // MARK: Actions

    private func toggle(_ row: TuiRow?) {
        switch row {
        case .category(_, let items):
            let selectable = items.filter(PlanSelection.isSelectable)
            plan.setSelected(selectable, !selectable.allSatisfy(plan.isSelected))
        case .item(let item):
            if !PlanSelection.isSelectable(item) {
                message = item.action == .moveBack ? "Press b to move it back." : "This item has no action. Info only."
            }
            plan.toggle(item)
        case .problem, nil:
            break
        }
    }

    private func expandOrCollapse(_ row: TuiRow?, key: Terminal.Key, rows: [TuiRow]) {
        switch row {
        case .category(let category, _):
            if key == .left {
                expanded.remove(category)
            } else if key == .right {
                expanded.insert(category)
            } else if expanded.contains(category) {
                expanded.remove(category)
            } else {
                expanded.insert(category)
            }
        case .item(let item) where key == .left:
            expanded.remove(item.category)
            cursor = rows.firstIndex { row in
                if case .category(let category, _) = row { return category == item.category }
                return false
            } ?? cursor
        default:
            break
        }
    }

    private func switchMoveOrDelete(_ row: TuiRow?) {
        guard case .item(let item) = row else {
            message = "Select an item first."
            return
        }
        if item.canMove {
            plan.setMove(item, plan.effectiveAction(item) != .move)
        } else if item.offersManualMove {
            guard usableDiskRoot != nil else {
                message = "Choose an external disk first: press d."
                return
            }
            askManualMove(item)
        } else {
            message = "This item cannot be moved."
        }
    }

    private func askManualMove(_ item: ScanItem) {
        let why = item.category == .largeUnknown
            ? "It is not in the catalog, so nobody checked that its app works from an external disk."
            : "Some apps delete and recreate their cache folder, and that removes the link."
        question = Question(text: "Move \(item.title) to the external disk now? \(why) (y/n)") { [weak self] in
            self?.startOptimize([item.with(action: .move)])
        }
    }

    private func askIgnore(_ row: TuiRow?) {
        guard case .item(let item) = row, item.path.hasPrefix("/") else {
            message = "Select an item with a folder path first."
            return
        }
        let file = PathTools.abbreviate(options.ignorePath, home: options.home)
        question = Question(text: "Hide \(item.title) for good? It is never listed or cleaned again. To undo, delete its line in \(file). (y/n)") { [weak self] in
            guard let self else {
                return
            }
            do {
                try IgnoreList.add(item.path, options: self.options)
                self.startScan()
            } catch {
                self.message = "Could not save the ignore list: \(error.localizedDescription)"
            }
        }
    }

    private func askMoveBack(_ row: TuiRow?) {
        guard case .item(let item) = row, item.action == .moveBack else {
            message = "Move back works on items in \"\(ItemCategory.alreadyMoved.title)\"."
            return
        }
        question = Question(text: "Move \(item.title) back to this Mac? The copy on the external disk stays. (y/n)") { [weak self] in
            self?.startOptimize([item])
        }
    }

    private func askFix(_ row: TuiRow?) {
        guard case .problem(let problem) = row else {
            message = "Select a problem first."
            return
        }
        switch problem.kind {
        case .strayNestedLink, .brokenLink:
            guard let path = problem.path else {
                return
            }
            question = Question(text: "Remove the link \(path)? Only the link goes; the data stays. (y/n)") { [weak self] in
                do {
                    try ProblemFixer.removeLink(at: path)
                    self?.startScan()
                } catch {
                    self?.message = "Could not remove the link: \(error.localizedDescription)"
                }
            }
        case .timeMachineSnapshots:
            question = Question(text: "Delete local Time Machine snapshots? Needs your admin password. (y/n)") { [weak self] in
                self?.message = ProblemFixer.deleteLocalSnapshots()
                self?.startScan()
            }
        case .diskNotMounted:
            message = "Connect the disk, then press s."
        case .lowFreeSpace:
            break
        }
    }

    private func nextDisk() {
        refreshDiskChoices()
        let usable = diskChoices.filter { $0.problem == nil }.map(\.path)
        guard !usable.isEmpty else {
            message = diskChoices.first?.problem.map { "No usable disk: \($0)" } ?? "No external disk is connected."
            return
        }
        let next = usable.firstIndex(of: diskRoot ?? "").map { (usable.index(after: $0)) % usable.count } ?? 0
        diskRoot = usable[next]
        SharedSettings.moveDiskRoot = diskRoot
        message = "Moves go to \(diskRoot ?? "")."
    }

    private func openConfirm() {
        let items = chosenItems
        guard !items.isEmpty, !snapshot.isScanning else {
            message = snapshot.isScanning ? "Wait for the scan to finish." : "Nothing is checked. Use space to check items."
            return
        }
        refreshDiskChoices()
        runningApps = Set(items.compactMap(RunningApps.owner)).sorted()
        confirmScroll = 0
        screen = .confirm
    }

    private func refreshDiskChoices() {
        diskChoices = options.disks.choices(internalPath: options.home)
    }

    private func syncFromBackground() {
        snapshot = background.read()
        if snapshot.scanVersion != seenScanVersion, let report = snapshot.report {
            seenScanVersion = snapshot.scanVersion
            plan = PlanSelection.defaults(for: report.items)
        }
        if let error = snapshot.errorText {
            message = error
            background.modify { $0.errorText = nil }
        }
    }

    // MARK: Background work

    func startScan() {
        guard !snapshot.isScanning && !background.read().isScanning else {
            return
        }
        let catalog = catalog
        let options = options
        let background = background
        background.modify { $0.isScanning = true; $0.scanStep = "" }
        DispatchQueue.global().async {
            do {
                let report = try Scanner.scan(catalog: catalog, options: options) { step in
                    background.modify { $0.scanStep = step }
                }
                var version = 0
                background.modify {
                    $0.report = report
                    $0.scanVersion += 1
                    version = $0.scanVersion
                    $0.isScanning = false
                    $0.isScanningExternal = true
                }
                // Sizes from the last scan appear at once, marked with "~"; the new count replaces them.
                let cachedReport = ExternalScanner.scan(report: report, catalog: catalog, options: options, mode: .cachedOnly)
                background.modify {
                    if $0.scanVersion == version {
                        $0.report = cachedReport
                    }
                }
                let fullReport = ExternalScanner.scan(report: report, catalog: catalog, options: options, mode: .fresh)
                background.modify {
                    // A newer scan wins over this slow one.
                    if $0.scanVersion == version {
                        $0.report = fullReport
                    }
                    $0.isScanningExternal = false
                }
            } catch {
                background.modify { $0.isScanning = false; $0.errorText = "Scan failed: \(error.localizedDescription)" }
            }
        }
    }

    private func startOptimize(_ items: [ScanItem]) {
        let optimizer = Optimizer(catalog: catalog, options: options, ownerCheck: RunningApps.owner)
        let mode = deleteMode
        let diskRoot = usableDiskRoot
        let background = background
        background.modify {
            $0.isOptimizing = true
            $0.result = nil
            $0.isCancelRequested = false
            $0.optimizeIndex = 0
            $0.optimizeStep = ""
        }
        progressTotal = items.count
        screen = .progress
        DispatchQueue.global().async {
            let result = optimizer.run(
                items: items, mode: mode, diskRoot: diskRoot,
                isCancelled: { background.read().isCancelRequested }
            ) { index, item, stage in
                background.modify {
                    $0.optimizeIndex = index
                    $0.optimizeStep = stage.isEmpty ? item.title : "\(stage): \(item.title)"
                }
            }
            background.modify { $0.result = result; $0.isOptimizing = false }
        }
    }

    func listHeight() -> Int {
        return max(terminal.height - headerLineCount - TuiApp.FOOTER_LINES, TuiApp.MIN_LIST_LINES)
    }
}
