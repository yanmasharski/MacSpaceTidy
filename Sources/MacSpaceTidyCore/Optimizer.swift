import Foundation

/// Deletes the chosen items. Checks every item again right before the action.
public struct Optimizer: Sendable {
    /// Returns the name of a running app that owns the item, or nil.
    public typealias OwnerCheck = @Sendable (ScanItem) -> String?
    /// Runs shell commands as root. Returns nil on success, else an error text.
    public typealias AdminRunner = @Sendable ([String]) -> String?
    /// Item index, item, and the current stage text ("Deleting", "Copying", …).
    public typealias Progress = @Sendable (Int, ScanItem, String) -> Void

    /// Why a move was skipped when no disk is chosen. The interfaces look for it to show a notice.
    public static let NO_DISK_REASON = "No external disk is chosen."

    private static let XCRUN = "/usr/bin/xcrun"
    private static let SIMULATOR_DELETE_TIMEOUT_SECONDS = 600.0

    public let catalog: Catalog
    public let options: ScanOptions
    public let ownerCheck: OwnerCheck
    public let adminRunner: AdminRunner
    public let mover: Mover

    public init(
        catalog: Catalog,
        options: ScanOptions,
        ownerCheck: @escaping OwnerCheck,
        adminRunner: @escaping AdminRunner = AdminShell.run,
        copier: @escaping Mover.Copier = Mover.ditto
    ) {
        self.catalog = catalog
        self.options = options
        self.ownerCheck = ownerCheck
        self.adminRunner = adminRunner
        self.mover = Mover(catalog: catalog, options: options, copier: copier)
    }

    /// `diskRoot` is the external disk for `.move` items. Nil skips them.
    public func run(
        items: [ScanItem],
        mode: DeleteMode,
        diskRoot: String? = nil,
        isCancelled: @Sendable () -> Bool,
        progress: Progress? = nil
    ) -> OptimizeResult {
        let diskBefore = DiskSpace.read(path: options.home) ?? DiskSpace(totalBytes: 0, freeBytes: 0)
        var outcomes: [ItemOutcome] = []
        var adminItems: [ScanItem] = []
        var wasCancelled = false

        // Admin items go last, in one batch, so the password is asked once.
        let userItems = items.filter { !$0.needsAdmin }
        for (index, item) in userItems.enumerated() {
            if isCancelled() {
                wasCancelled = true
                break
            }
            progress?(index, item, "")
            let status = ignoreRefusal(item).map(ItemOutcome.Status.skipped)
                ?? perform(item, mode: mode, diskRoot: diskRoot) { stage in progress?(index, item, stage) }
            outcomes.append(ItemOutcome(item: item, status: status))
            log(item, status, mode: mode)
        }
        if !wasCancelled {
            for item in items where item.needsAdmin {
                if let reason = ignoreRefusal(item) ?? refusalReason(item) {
                    outcomes.append(ItemOutcome(item: item, status: .skipped(reason)))
                } else {
                    adminItems.append(item)
                }
            }
        }
        if let first = adminItems.first {
            progress?(userItems.count, first, "Waiting for the admin password")
            let error = adminRunner(adminItems.map { FolderCleaner.adminCommand(for: $0.path) })
            for item in adminItems {
                let status: ItemOutcome.Status = FolderCleaner.isClean(item.path) ? .done : .failed(error ?? "The folder is not empty.")
                outcomes.append(ItemOutcome(item: item, status: status))
                log(item, status, mode: .deleteNow)
            }
        }
        let diskAfter = DiskSpace.read(path: options.home) ?? diskBefore
        return OptimizeResult(outcomes: outcomes, diskBefore: diskBefore, diskAfter: diskAfter, wasCancelled: wasCancelled)
    }

    /// Nil when the item is not in the user's ignore list. An unreadable list refuses everything.
    private func ignoreRefusal(_ item: ScanItem) -> String? {
        guard item.path.hasPrefix("/") else {
            return nil
        }
        guard let list = IgnoreList.read(options: options) else {
            return "The ignore list could not be read."
        }
        return IgnoreList.isIgnored(item.path, in: list) ? "It is in your ignore list." : nil
    }

    /// Writes finished cleans to the clean log. Skipped items did nothing, so they are not logged. Moves have their own journal.
    private func log(_ item: ScanItem, _ status: ItemOutcome.Status, mode: DeleteMode) {
        let action: String
        switch item.action {
        case .trashOnly: action = "trash"
        case .delete, .cleanExternal, .deleteExternalCopy: action = mode == .trash && !item.needsAdmin ? "trash" : "delete"
        case .deleteSimulatorRuntime: action = "delete"
        default: return
        }
        let result: String
        switch status {
        case .done: result = "done"
        case .failed(let reason): result = "failed: \(reason)"
        case .skipped: return
        }
        try? CleanLog.append(CleanLog.Record(date: Date(), action: action, path: item.path, bytes: item.size.bytes, result: result), to: options.cleanLogPath)
    }

    /// Nil when the item may be deleted now.
    public func refusalReason(_ item: ScanItem) -> String? {
        if item.action == .deleteSimulatorRuntime {
            return nil
        }
        guard item.action == .delete || item.action == .trashOnly else {
            return "This item cannot be deleted."
        }
        // Your own files and leftovers: only direct entries of the Downloads folder or of the leftover folders,
        // and never a folder with a git repository inside.
        if item.action == .trashOnly && item.category == .projects, let reason = ProjectScanner.refusal(item.path, options: options) {
            return reason
        }
        if item.action == .trashOnly && item.category != .projects
            && (item.path as NSString).deletingLastPathComponent != options.downloadsPath && !LeftoverScanner.canTrash(item.path, options: options) {
            return "Only entries of the Downloads folder, of the leftover folders, and build folders of projects can be trashed."
        }
        // The Wine prefix may be a link to an external disk. Then its content is cleaned; the link and the folder stay.
        if item.action == .trashOnly && PathTools.isSymlink(item.path) && item.path == LeftoverScanner.winePrefix(options: options) {
            return LeftoverScanner.linkedPrefixRefusal(options: options)
        }
        if catalog.isProtected(item.path, home: options.home) {
            return "Protected path."
        }
        if !PathTools.exists(item.path) {
            return "Already gone."
        }
        if PathTools.isSymlink(item.path) {
            return "It is a link now. Scan again."
        }
        if options.disks.isOnExternalDisk(PathTools.resolved(item.path)) {
            return "It is inside a folder on an external disk."
        }
        if !isInsideAllowedFolder(item) {
            return "Outside the folders MacSpaceTidy may clean."
        }
        if PathTools.isDirectory(item.path + "/.git") {
            return "It is a git repository."
        }
        return nil
    }

    /// Defense in depth: delete only inside your home folder or `/Users/Shared`.
    /// The exception is an admin item that the catalog itself lists, like the system simulator cache.
    private func isInsideAllowedFolder(_ item: ScanItem) -> Bool {
        let resolved = PathTools.resolved(item.path)
        let allowed = [options.home, PathTools.resolved(options.home), Mover.SHARED_USERS_FOLDER]
        if allowed.contains(where: { PathTools.isSameOrInside(resolved, folder: $0) && resolved != $0 }) {
            return true
        }
        return item.needsAdmin && catalog.entries.contains { $0.needsAdmin && PathTools.expand($0.path, home: options.home) == item.path }
    }

    private func perform(_ item: ScanItem, mode: DeleteMode, diskRoot: String?, stage: @escaping Mover.Stage) -> ItemOutcome.Status {
        if let app = ownerCheck(item) {
            return .skipped("\(app) is running. Quit it first.")
        }
        switch item.action {
        case .move:
            guard let diskRoot else {
                return .skipped(Optimizer.NO_DISK_REASON)
            }
            return mover.move(item, diskRoot: diskRoot, stage: stage)
        case .moveBack:
            return mover.moveBack(item, stage: stage)
        case .cleanExternal, .deleteExternalCopy:
            stage("Cleaning")
            return cleanExternal(item, mode: mode)
        case .trashOnly:
            if let reason = refusalReason(item) {
                return .skipped(reason)
            }
            stage("Moving to the Trash")
            do {
                if PathTools.isSymlink(item.path), let target = PathTools.linkTarget(item.path) {
                    // A link is never deleted: only what is inside the folder behind it goes to the Trash.
                    try FolderCleaner.clean(target, mode: .trash)
                } else {
                    try FolderCleaner.remove(item.path, mode: .trash)
                }
                return .done
            } catch {
                return .failed(error.localizedDescription)
            }
        case .delete, .deleteSimulatorRuntime, .cleanInApp, .info, .never:
            break
        }
        if let reason = refusalReason(item) {
            return .skipped(reason)
        }
        stage("Deleting")
        if item.action == .deleteSimulatorRuntime {
            return deleteSimulatorRuntime(item)
        }
        do {
            try FolderCleaner.clean(item.path, mode: mode)
            return .done
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Nil when the external clean may run.
    public func cleanExternalRefusal(_ item: ScanItem) -> String? {
        guard item.action == .cleanExternal || item.action == .deleteExternalCopy else {
            return "This item cannot be cleaned."
        }
        let folder = PathTools.linkTarget(item.path) ?? item.path
        guard let root = options.disks.volumeRoot(of: folder), options.disks.isMounted(folder) else {
            return "It is not on a connected external disk."
        }
        let toolFolder = (root as NSString).appendingPathComponent(Mover.FOLDER_NAME)
        if folder == root || folder == toolFolder || !PathTools.isDirectory(folder) {
            return "Protected path."
        }
        if !PathTools.isSymlink(item.path) && !options.disks.isOnExternalDisk(item.path) {
            return "Protected path."
        }
        // A whole folder is deleted only inside the tool's own folder, and only when nothing links to it.
        if item.action == .deleteExternalCopy && (PathTools.isSymlink(item.path) || !folder.hasPrefix(toolFolder + "/")) {
            return "Only copies inside \(toolFolder) can be deleted whole."
        }
        return nil
    }

    private func cleanExternal(_ item: ScanItem, mode: DeleteMode) -> ItemOutcome.Status {
        if let reason = cleanExternalRefusal(item) {
            return .skipped(reason)
        }
        let folder = PathTools.linkTarget(item.path) ?? item.path
        do {
            if item.action == .deleteExternalCopy {
                try FolderCleaner.remove(folder, mode: mode)
            } else {
                try FolderCleaner.clean(folder, mode: mode)
            }
            return .done
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func deleteSimulatorRuntime(_ item: ScanItem) -> ItemOutcome.Status {
        let identifier = String(item.path.dropFirst(Scanner.SIMULATOR_PATH_PREFIX.count))
        let result = CommandRunner.run(
            Optimizer.XCRUN,
            ["simctl", "runtime", "delete", identifier],
            timeoutSeconds: Optimizer.SIMULATOR_DELETE_TIMEOUT_SECONDS
        )
        guard let result else {
            return .failed("simctl did not finish in time.")
        }
        return result.exitCode == 0 ? .done : .failed("simctl failed with code \(result.exitCode).")
    }
}
