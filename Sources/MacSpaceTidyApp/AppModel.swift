import Foundation
import MacSpaceTidyCore
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var report: ScanReport?
    var isScanning = false
    var isScanningExternal = false
    /// Categories of the running scan that are still being counted. Shown as dimmed rows.
    var pendingCategories: Set<ItemCategory> = []
    var scanStep = ""
    var errorText: String?
    var plan = PlanSelection()
    var activeSheet: ActiveSheet?
    var optimizeStep = ""
    var optimizeIndex = 0
    var optimizeTotal = 0
    var result: OptimizeResult?
    var diskChoices: [DiskChoice] = []
    /// Demo data for snapshots: nothing is saved or scanned.
    var isDemo = false
    var initiallyExpanded: Set<ItemCategory> = []
    var deleteMode: DeleteMode {
        didSet {
            if !isDemo {
                SharedSettings.deleteMode = deleteMode
            }
        }
    }
    /// External disks searched for large files and duplicates too. Takes effect on the next scan.
    var extraScanDisks: Set<String> {
        didSet {
            if !isDemo {
                SharedSettings.extraScanDisks = extraScanDisks.sorted()
            }
        }
    }
    /// External disks the separate duplicate search covers. This Mac is always searched.
    var duplicateDisks: Set<String> {
        didSet {
            if !isDemo {
                SharedSettings.duplicateScanDisks = duplicateDisks.sorted()
            }
        }
    }
    var isScanningDuplicates = false
    var duplicateStep = ""
    /// True once a duplicate search of the current report has finished, so "none found" can be told from "not searched yet".
    var hasSearchedDuplicates = false
    /// External disk for moves. Chosen once, remembered.
    var moveDiskRoot: String? {
        didSet {
            if !isDemo {
                SharedSettings.moveDiskRoot = moveDiskRoot
            }
        }
    }

    private let catalog: Catalog?
    private var seenItemIds: Set<String> = []
    private var cancelFlag = CancelFlag()
    /// A newer scan makes the result of an older external scan stale.
    private var scanGeneration = 0
    private var duplicateGeneration = 0
    private var duplicateCancel = CancelFlag()

    init() {
        deleteMode = SharedSettings.deleteMode
        moveDiskRoot = SharedSettings.moveDiskRoot
        extraScanDisks = Set(SharedSettings.extraScanDisks)
        duplicateDisks = Set(SharedSettings.duplicateScanDisks)
        do {
            catalog = try Catalog.loadBundled()
        } catch {
            catalog = nil
            errorText = "The rules catalog could not be loaded: \(error.localizedDescription)"
        }
    }

    /// Selected items with the action the user chose (move or delete).
    var selectedItems: [ScanItem] {
        return plan.chosenItems(from: report?.items ?? [])
    }

    func effectiveAction(_ item: ScanItem) -> ItemAction {
        return plan.effectiveAction(item)
    }

    var selectedBytes: Int64 {
        return selectedItems.reduce(0) { $0 + $1.size.bytes }
    }

    var isOptimizing: Bool {
        return activeSheet == .progress && result == nil
    }

    var usableDiskRoot: String? {
        guard let moveDiskRoot, diskChoices.contains(where: { $0.path == moveDiskRoot && $0.problem == nil }) else {
            return nil
        }
        return moveDiskRoot
    }

    func refreshDiskChoices() {
        if isDemo {
            return
        }
        diskChoices = ExternalDisks().choices(internalPath: NSHomeDirectory())
    }

    /// Dry run of a move: nil when it can start, else the reason why not.
    func moveRefusal(_ item: ScanItem) -> String? {
        if isDemo {
            return nil
        }
        guard let catalog else {
            return "The rules catalog is not loaded."
        }
        guard let diskRoot = usableDiskRoot else {
            return "Choose an external disk."
        }
        return Mover(catalog: catalog, options: .standard()).moveRefusal(item, diskRoot: diskRoot)
    }

    func scan() {
        guard let catalog, !isScanning else {
            return
        }
        isScanning = true
        scanGeneration += 1
        stopDuplicateSearch()
        hasSearchedDuplicates = false
        scanStep = ""
        errorText = nil
        plan = PlanSelection()
        seenItemIds = []
        // Duplicates are a separate search: it reads whole files and would hold the main scan for a long time.
        var scanOptions = ScanOptions.standard()
        scanOptions.scansDuplicates = false
        let options = scanOptions
        Task.detached {
            do {
                let report = try Scanner.scan(catalog: catalog, options: options, progress: { step in
                    Task { @MainActor in self.scanStep = step }
                }, onPartial: { partial, pending in
                    Task { @MainActor in self.showPartial(partial, pending: pending) }
                })
                await self.finishScan(report)
            } catch {
                await self.failScan(error)
            }
        }
    }

    /// The separate duplicate search: this Mac plus the chosen disks. Its groups join the current report.
    func scanDuplicates() {
        guard !isScanning, !isScanningDuplicates, report != nil else {
            return
        }
        isScanningDuplicates = true
        duplicateStep = ""
        pendingCategories.insert(.duplicates)
        duplicateCancel = CancelFlag()
        let flag = duplicateCancel
        let generation = duplicateGeneration
        let options = ScanOptions.standard()
        Task.detached {
            let ignored = IgnoreList.read(options: options) ?? []
            let items = DuplicateScanner.items(options: options, ignored: ignored, progress: { step in
                Task { @MainActor in self.duplicateStep = step }
            }, isCancelled: { flag.isSet })
            await self.finishDuplicates(items, cancelled: flag.isSet, generation: generation)
        }
    }

    func cancelDuplicates() {
        duplicateCancel.set()
    }

    /// A new main scan drops the old groups: files may be gone, and the duplicate search is started again by hand.
    private func stopDuplicateSearch() {
        duplicateCancel.set()
        duplicateGeneration += 1
        isScanningDuplicates = false
        pendingCategories.remove(.duplicates)
    }

    private func finishDuplicates(_ items: [ScanItem], cancelled: Bool, generation: Int) {
        guard generation == duplicateGeneration else {
            return
        }
        isScanningDuplicates = false
        pendingCategories.remove(.duplicates)
        guard !cancelled, let report else {
            return
        }
        self.report = merged(report, duplicates: items)
        hasSearchedDuplicates = true
        plan.addDefaults(for: items.filter { seenItemIds.insert($0.id).inserted })
    }

    private func merged(_ base: ScanReport, duplicates: [ScanItem]) -> ScanReport {
        let items = (base.items.filter { $0.category != .duplicates } + duplicates).sorted { first, second in
            first.size.bytes != second.size.bytes ? first.size.bytes > second.size.bytes : first.title < second.title
        }
        return ScanReport(disk: base.disk, items: items, problems: base.problems, externalDisks: base.externalDisks)
    }

    /// Hides the item for good: it is never listed or cleaned again. The user undoes it by editing the ignore file.
    func ignore(_ item: ScanItem) {
        do {
            try IgnoreList.add(item.path, options: .standard())
            scan()
        } catch {
            errorText = "Could not save the ignore list: \(error.localizedDescription)"
        }
    }

    func optimize() {
        run(selectedItems)
    }

    /// Runs one item outside the checkbox plan: "Move back", or a manual move of an unknown folder.
    func runSingle(_ item: ScanItem) {
        refreshDiskChoices()
        run([item])
    }

    private func run(_ items: [ScanItem]) {
        guard let catalog else {
            return
        }
        let mode = deleteMode
        let diskRoot = usableDiskRoot
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        result = nil
        optimizeIndex = 0
        optimizeTotal = items.count
        optimizeStep = ""
        activeSheet = .progress
        Task.detached {
            let optimizer = Optimizer(catalog: catalog, options: .standard(), ownerCheck: RunningApps.owner)
            let result = optimizer.run(items: items, mode: mode, diskRoot: diskRoot, isCancelled: { flag.isSet }) { index, item, stage in
                Task { @MainActor in
                    self.optimizeIndex = index
                    self.optimizeStep = stage.isEmpty ? item.title : "\(stage): \(item.title)"
                }
            }
            await self.finishOptimize(result)
        }
    }

    func cancelOptimize() {
        cancelFlag.set()
    }

    func closeResult() {
        activeSheet = nil
        result = nil
        scan()
    }

    func removeLink(_ path: String) {
        do {
            try ProblemFixer.removeLink(at: path)
            scan()
        } catch {
            errorText = "Could not remove the link: \(error.localizedDescription)"
        }
    }

    func deleteSnapshots() {
        Task.detached {
            let error = ProblemFixer.deleteLocalSnapshots()
            await self.finishFix(error)
        }
    }

    /// A finished block of the scan: its numbers appear at once, with the default checks for its new items.
    private func showPartial(_ partial: ScanReport, pending: Set<ItemCategory>) {
        guard isScanning else {
            return
        }
        report = partial
        pendingCategories = pending
        plan.addDefaults(for: partial.items.filter { seenItemIds.insert($0.id).inserted })
    }

    private func finishScan(_ report: ScanReport) {
        self.report = report
        pendingCategories = []
        plan.addDefaults(for: report.items.filter { seenItemIds.insert($0.id).inserted })
        refreshDiskChoices()
        scanExternal(report)
        isScanning = false
    }

    /// Slow: measures folders on external disks, then adds what can be cleaned there.
    private func scanExternal(_ report: ScanReport) {
        guard let catalog, report.items.contains(where: { $0.category == .alreadyMoved }) else {
            return
        }
        let generation = scanGeneration
        isScanningExternal = true
        Task.detached {
            // Sizes from the last scan appear at once, marked as old; the new count replaces them.
            let cachedReport = ExternalScanner.scan(report: report, catalog: catalog, options: .standard(), mode: .cachedOnly)
            await self.showExternalScan(cachedReport, generation: generation, isFinal: false)
            let fullReport = ExternalScanner.scan(report: report, catalog: catalog, options: .standard(), mode: .fresh)
            await self.showExternalScan(fullReport, generation: generation, isFinal: true)
        }
    }

    private func showExternalScan(_ newReport: ScanReport, generation: Int, isFinal: Bool) {
        guard generation == scanGeneration else {
            return
        }
        // The external scan started from a report without duplicates; do not lose the groups found meanwhile.
        let found = report?.items.filter { $0.category == .duplicates } ?? []
        report = found.isEmpty ? newReport : merged(newReport, duplicates: found)
        isScanningExternal = !isFinal
    }

    private func failScan(_ error: Error) {
        pendingCategories = []
        errorText = "Scan failed: \(error.localizedDescription)"
        isScanning = false
    }

    private func finishOptimize(_ result: OptimizeResult) {
        self.result = result
    }

    private func finishFix(_ error: String?) {
        errorText = error
        scan()
    }
}
