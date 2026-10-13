import Foundation

/// Moves a folder to an external disk and leaves a link, or copies a moved folder back.
/// Copy first, check the copy, swap, check the link, only then delete the old data.
public struct Mover: Sendable {
    /// Copies `source` to `destination` (which must not exist). Returns nil on success, else an error text.
    public typealias Copier = @Sendable (_ source: String, _ destination: String) -> String?
    public typealias Stage = @Sendable (String) -> Void

    public static let FOLDER_NAME = "MacSpaceTidy"
    public static let OLD_SUFFIX = ".mst-old"
    public static let RETURN_SUFFIX = ".mst-return"
    /// Keep this much more free space than the folder needs.
    public static let FREE_SPACE_FACTOR = 1.1
    public static let SHARED_USERS_FOLDER = "/Users/Shared"
    private static let DITTO = "/usr/bin/ditto"
    private static let COPY_TIMEOUT_SECONDS = 12.0 * 60 * 60

    public let catalog: Catalog
    public let options: ScanOptions
    public let copier: Copier

    public init(catalog: Catalog, options: ScanOptions, copier: @escaping Copier = Mover.ditto) {
        self.catalog = catalog
        self.options = options
        self.copier = copier
    }

    /// `ditto` keeps hard links, links, permissions, and extended attributes.
    public static func ditto(_ source: String, _ destination: String) -> String? {
        guard let result = CommandRunner.run(DITTO, [source, destination], timeoutSeconds: COPY_TIMEOUT_SECONDS) else {
            return "The copy did not finish."
        }
        return result.exitCode == 0 ? nil : "The copy failed (ditto code \(result.exitCode))."
    }

    /// `<disk>/MacSpaceTidy/<original absolute path>`.
    public static func destination(for source: String, diskRoot: String) -> String {
        return ((diskRoot as NSString).appendingPathComponent(FOLDER_NAME) as NSString).appendingPathComponent(source)
    }

    // MARK: Move to the external disk

    /// Nil when the move may start. This is the dry run: it changes nothing.
    public func moveRefusal(_ item: ScanItem, diskRoot: String) -> String? {
        let source = item.path
        guard item.action == .move else {
            return "This item cannot be moved."
        }
        guard PathTools.isSameOrInside(source, folder: options.home) || PathTools.isSameOrInside(source, folder: Mover.SHARED_USERS_FOLDER) else {
            return "Only folders in your home folder or /Users/Shared can be moved. Others are read before external disks connect."
        }
        if catalog.isProtected(source, home: options.home) {
            return "Protected path."
        }
        if PathTools.isSymlink(source) {
            return "It is already a link."
        }
        guard PathTools.exists(source) else {
            return "The folder is gone. Scan again."
        }
        if options.disks.isOnExternalDisk(PathTools.resolved(source)) {
            return "It is already on an external disk."
        }
        if let problem = options.disks.problem(with: diskRoot) {
            return problem
        }
        if PathTools.exists(Mover.destination(for: source, diskRoot: diskRoot)) {
            return "The destination already exists: \(Mover.destination(for: source, diskRoot: diskRoot))"
        }
        if PathTools.exists(source + Mover.OLD_SUFFIX) {
            return "A leftover \(Mover.OLD_SUFFIX) folder from an earlier move exists. Check it first."
        }
        let neededBytes = Int64(Double(item.size.bytes) * Mover.FREE_SPACE_FACTOR)
        if let free = DiskSpace.read(path: diskRoot)?.freeBytes, free < neededBytes {
            return "Not enough space on the disk: needs \(ByteText.format(neededBytes)), has \(ByteText.format(free))."
        }
        return nil
    }

    public func move(_ item: ScanItem, diskRoot: String, stage: Stage? = nil) -> ItemOutcome.Status {
        if let reason = moveRefusal(item, diskRoot: diskRoot) {
            return .skipped(reason)
        }
        let source = item.path
        let destination = Mover.destination(for: source, diskRoot: diskRoot)
        let old = source + Mover.OLD_SUFFIX
        let fileManager = FileManager.default

        stage?("Copying")
        let before = TreeSummary.make(path: source)
        guard before.isComplete else {
            return .skipped("Some files could not be read. Give Full Disk Access and try again.")
        }
        do {
            try fileManager.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        } catch {
            return .failed("Could not create the folder on the disk: \(error.localizedDescription)")
        }
        if let error = copier(source, destination) {
            try? fileManager.removeItem(atPath: destination)
            return .failed(error)
        }

        stage?("Checking the copy")
        if TreeSummary.make(path: destination) != before {
            try? fileManager.removeItem(atPath: destination)
            return .failed("The copy is not the same as the original. Nothing changed.")
        }
        if TreeSummary.make(path: source) != before {
            try? fileManager.removeItem(atPath: destination)
            return .failed("Files changed during the copy. Quit the app that uses the folder and try again.")
        }

        stage?("Replacing with a link")
        do {
            try fileManager.moveItem(atPath: source, toPath: old)
        } catch {
            try? fileManager.removeItem(atPath: destination)
            return .failed("Could not rename the folder: \(error.localizedDescription)")
        }
        do {
            try fileManager.createSymbolicLink(atPath: source, withDestinationPath: destination)
        } catch {
            try? fileManager.moveItem(atPath: old, toPath: source)
            try? fileManager.removeItem(atPath: destination)
            return .failed("Could not create the link: \(error.localizedDescription)")
        }
        if PathTools.linkTarget(source) != destination || TreeSummary.make(path: source) != before {
            try? fileManager.removeItem(atPath: source)
            try? fileManager.moveItem(atPath: old, toPath: source)
            try? fileManager.removeItem(atPath: destination)
            return .failed("The link did not work. The folder is back as it was.")
        }

        stage?("Removing the old copy")
        try? MoveJournal.append(
            MoveJournal.Record(date: Date(), kind: MoveJournal.KIND_MOVE, source: source, destination: destination),
            to: options.journalPath
        )
        do {
            try fileManager.removeItem(atPath: old)
        } catch {
            return .failed("Moved, but the old copy \(old) could not be deleted: \(error.localizedDescription)")
        }
        return .done
    }

    // MARK: Move back to the internal disk

    public func moveBackRefusal(_ item: ScanItem) -> String? {
        let link = item.path
        guard item.action == .moveBack, let target = PathTools.linkTarget(link) else {
            return "It is not a link to an external disk."
        }
        guard options.disks.isOnExternalDisk(target) else {
            return "It is not a link to an external disk."
        }
        guard options.disks.isMounted(target), PathTools.exists(target) else {
            return "The external disk is not connected."
        }
        if PathTools.exists(link + Mover.RETURN_SUFFIX) {
            return "A leftover \(Mover.RETURN_SUFFIX) folder from an earlier attempt exists. Check it first."
        }
        return nil
    }

    /// The copy on the external disk stays. The user deletes it when sure.
    public func moveBack(_ item: ScanItem, stage: Stage? = nil) -> ItemOutcome.Status {
        if let reason = moveBackRefusal(item) {
            return .skipped(reason)
        }
        let link = item.path
        guard let target = PathTools.linkTarget(link) else {
            return .skipped("It is not a link.")
        }
        let incoming = link + Mover.RETURN_SUFFIX
        let fileManager = FileManager.default

        stage?("Measuring")
        let neededBytes = Int64(Double(FolderSize.measure(path: target).bytes) * Mover.FREE_SPACE_FACTOR)
        let parent = (link as NSString).deletingLastPathComponent
        if let free = DiskSpace.read(path: parent)?.freeBytes, free < neededBytes {
            return .skipped("Not enough space on this Mac: needs \(ByteText.format(neededBytes)), has \(ByteText.format(free)).")
        }
        let before = TreeSummary.make(path: target)
        guard before.isComplete else {
            return .skipped("Some files on the external disk could not be read.")
        }

        stage?("Copying back")
        if let error = copier(target, incoming) {
            try? fileManager.removeItem(atPath: incoming)
            return .failed(error)
        }
        stage?("Checking the copy")
        if TreeSummary.make(path: incoming) != before || TreeSummary.make(path: target) != before {
            try? fileManager.removeItem(atPath: incoming)
            return .failed("The copy is not the same as the original. Nothing changed.")
        }

        stage?("Replacing the link")
        do {
            try fileManager.removeItem(atPath: link)
        } catch {
            try? fileManager.removeItem(atPath: incoming)
            return .failed("Could not remove the link: \(error.localizedDescription)")
        }
        do {
            try fileManager.moveItem(atPath: incoming, toPath: link)
        } catch {
            try? fileManager.createSymbolicLink(atPath: link, withDestinationPath: target)
            return .failed("Could not put the folder back: \(error.localizedDescription). The link is restored.")
        }
        try? MoveJournal.append(
            MoveJournal.Record(date: Date(), kind: MoveJournal.KIND_MOVE_BACK, source: target, destination: link),
            to: options.journalPath
        )
        return .done
    }
}
