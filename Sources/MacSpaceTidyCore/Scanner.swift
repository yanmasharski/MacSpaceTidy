import Foundation

/// Read-only scan: sizes, suggestions, and problems. Changes nothing on disk.
public enum Scanner {
    public typealias Progress = @Sendable (String) -> Void

    public static let SIMULATOR_PATH_PREFIX = "simctl:"
    private static let MOVED_REASON = "Already moved to an external disk. You can move it back."
    private static let UNKNOWN_REASON = "Large folder not in the catalog. Check what it is before you delete or move it."
    private static let SIMULATOR_REASON = "iOS simulator runtime. Keep the versions you test on. Xcode can download it again."

    public static func scan(catalog: Catalog, options: ScanOptions, progress: Progress? = nil) throws -> ScanReport {
        guard let disk = DiskSpace.read(path: options.home) else {
            throw CocoaError(.fileReadUnknown)
        }
        let links = LinkFinder.findLinks(roots: options.linkRoots, maxDepth: options.linkSearchDepth)
        var problems = ProblemFinder.linkProblems(links: links, disks: options.disks)
        let strayLinks = Set(problems.filter { $0.kind == .strayNestedLink }.compactMap { $0.path })

        var items: [String: ScanItem] = [:]
        for item in catalogItems(catalog: catalog, options: options, strayLinks: strayLinks, progress: progress) {
            items[item.path] = item
        }
        for link in links where items[link.path] == nil && !strayLinks.contains(link.path) {
            if let item = movedItem(path: link.path, target: link.target, options: options, progress: progress) {
                items[item.path] = item
            }
        }
        for item in largeUnknownItems(catalog: catalog, options: options, progress: progress) {
            items[item.path] = item
        }
        for item in DownloadsScanner.items(options: options, progress: progress) where items[item.path] == nil {
            items[item.path] = item
        }
        for item in LeftoverScanner.items(catalog: catalog, options: options, progress: progress) {
            // A leftover replaces a plain cache item of the same path. Inside a listed folder (Containers) it is
            // taken out of that folder's size, so the disk bar does not count it twice.
            let parentPath = (item.path as NSString).deletingLastPathComponent
            if items[item.path] == nil, let parent = items[parentPath] {
                let size = parent.size
                items[parentPath] = parent.with(size: FolderSize(
                    bytes: max(0, size.bytes - item.size.bytes), isIncomplete: size.isIncomplete, newestChange: size.newestChange
                ))
            }
            items[item.path] = item
        }

        if let problem = ProblemFinder.freeSpaceProblem(disk: disk) {
            problems.insert(problem, at: 0)
        }
        if options.usesSystemTools {
            progress?("Reading simulator runtimes")
            for item in simulatorItems() {
                items[item.path] = item
            }
            if let count = SystemTools.localSnapshotCount(), let problem = ProblemFinder.snapshotProblem(snapshotCount: count) {
                problems.append(problem)
            }
        }
        let sortedItems = items.values.sorted { first, second in
            if first.size.bytes != second.size.bytes {
                return first.size.bytes > second.size.bytes
            }
            return first.title < second.title
        }
        return ScanReport(disk: disk, items: sortedItems, problems: problems)
    }

    /// Concrete paths of an entry. A `/*` pattern skips children that have their own entry.
    public static func expandedPaths(of entry: CatalogEntry, catalog: Catalog, home: String) -> [String] {
        guard entry.isChildrenPattern else {
            return [PathTools.expand(entry.path, home: home)]
        }
        let folder = PathTools.expand(String(entry.path.dropLast(CatalogEntry.CHILDREN_SUFFIX.count)), home: home)
        let ownEntries = Set(catalog.entries.filter { !$0.isChildrenPattern }.map { PathTools.expand($0.path, home: home) })
        return PathTools.children(of: folder).filter { !ownEntries.contains($0) }
    }

    private static func catalogItems(catalog: Catalog, options: ScanOptions, strayLinks: Set<String>, progress: Progress?) -> [ScanItem] {
        var items: [ScanItem] = []
        for entry in catalog.entries where entry.action != .never {
            for path in expandedPaths(of: entry, catalog: catalog, home: options.home) where PathTools.exists(path) {
                if let target = PathTools.linkTarget(path) {
                    if !strayLinks.contains(path), let item = movedItem(path: path, target: target, options: options, progress: progress) {
                        items.append(item)
                    }
                    continue
                }
                // Inside a folder that is already moved: deleting it frees the external disk, not this one.
                if options.disks.isOnExternalDisk(PathTools.resolved(path)) {
                    continue
                }
                progress?(PathTools.abbreviate(path, home: options.home))
                let size = FolderSize.measure(path: path)
                // Small or already cleaned (an emptied folder stays) items are noise.
                if entry.action == .delete && size.bytes < options.minChildItemBytes {
                    continue
                }
                items.append(ScanItem(
                    path: path,
                    title: PathTools.abbreviate(path, home: options.home),
                    catalogId: entry.id,
                    category: entry.category,
                    action: entry.action,
                    risk: entry.risk,
                    checkedByDefault: entry.checkedByDefault,
                    needsAdmin: entry.needsAdmin,
                    ownerApps: entry.ownerApps,
                    reason: entry.reason,
                    size: size,
                    linkTarget: nil,
                    canMove: entry.canMove,
                    ageMatters: entry.ageMatters
                ))
            }
        }
        return items
    }

    /// Nil when the link does not point to a folder on an external disk.
    private static func movedItem(path: String, target: String, options: ScanOptions, progress: Progress?) -> ScanItem? {
        guard options.disks.isOnExternalDisk(target) else {
            return nil
        }
        let isMounted = options.disks.isMounted(target)
        if isMounted && !PathTools.exists(target) {
            return nil
        }
        // A disk that is not connected is reported as a problem, so its size is just zero here.
        var size = FolderSize(bytes: 0, isIncomplete: false)
        if isMounted && options.measuresMovedItems {
            progress?(PathTools.abbreviate(path, home: options.home))
            size = FolderSize.measure(path: target)
        }
        return ScanItem(
            path: path,
            title: PathTools.abbreviate(path, home: options.home),
            catalogId: nil,
            category: .alreadyMoved,
            action: .moveBack,
            risk: .low,
            checkedByDefault: false,
            needsAdmin: false,
            ownerApps: [],
            reason: MOVED_REASON,
            size: size,
            linkTarget: target
        )
    }

    // ponytail: a folder that contains a catalog path (like ~/.cache) is skipped as a whole,
    // so its other content is not listed. Go one level deeper if users miss big folders.
    private static func largeUnknownItems(catalog: Catalog, options: ScanOptions, progress: Progress?) -> [ScanItem] {
        let catalogPaths = catalog.entries.map { entry in
            let path = entry.isChildrenPattern ? String(entry.path.dropLast(CatalogEntry.CHILDREN_SUFFIX.count)) : entry.path
            return PathTools.expand(path, home: options.home)
        }
        var items: [ScanItem] = []
        for parent in options.unknownParents {
            for child in PathTools.children(of: parent) {
                // Downloads has its own list of old entries.
                let isKnown = catalogPaths.contains { PathTools.overlaps($0, child) } || options.unknownParents.contains(child)
                    || child == options.downloadsPath
                if isKnown || PathTools.isSymlink(child) || !PathTools.isDirectory(child) {
                    continue
                }
                progress?(PathTools.abbreviate(child, home: options.home))
                let size = FolderSize.measure(path: child)
                guard size.bytes >= options.largeUnknownBytes else {
                    continue
                }
                items.append(ScanItem(
                    path: child,
                    title: PathTools.abbreviate(child, home: options.home),
                    catalogId: nil,
                    category: .largeUnknown,
                    action: .info,
                    risk: .high,
                    checkedByDefault: false,
                    needsAdmin: false,
                    ownerApps: [],
                    reason: UNKNOWN_REASON,
                    size: size,
                    linkTarget: nil
                ))
            }
        }
        return items
    }

    private static func simulatorItems() -> [ScanItem] {
        return (SystemTools.simulatorRuntimes() ?? []).map { runtime in
            ScanItem(
                path: SIMULATOR_PATH_PREFIX + runtime.identifier,
                title: runtime.name,
                catalogId: nil,
                category: .simulators,
                action: .deleteSimulatorRuntime,
                risk: .medium,
                checkedByDefault: false,
                needsAdmin: false,
                ownerApps: ["Simulator"],
                reason: SIMULATOR_REASON,
                size: FolderSize(bytes: runtime.sizeBytes, isIncomplete: false),
                linkTarget: nil
            )
        }
    }
}
