import Foundation

/// Read-only scan: sizes, suggestions, and problems. Changes nothing on disk.
public enum Scanner {
    public typealias Progress = @Sendable (String) -> Void

    public static let SIMULATOR_PATH_PREFIX = "simctl:"
    private static let MOVED_REASON = "Already moved to an external disk. You can move it back."
    private static let UNKNOWN_REASON = "Large folder not in the catalog. Check what it is before you delete or move it."
    private static let SIMULATOR_REASON = "iOS simulator runtime. Keep the versions you test on. Xcode can download it again."

    /// Called after each block of the scan with what is known so far and the categories still being counted.
    public typealias Partial = @Sendable (ScanReport, Set<ItemCategory>) -> Void

    public static func scan(catalog: Catalog, options: ScanOptions, progress: Progress? = nil, onPartial: Partial? = nil) throws -> ScanReport {
        guard let disk = DiskSpace.read(path: options.home) else {
            throw CocoaError(.fileReadUnknown)
        }
        let links = LinkFinder.findLinks(roots: options.linkRoots, maxDepth: options.linkSearchDepth)
        var problems = ProblemFinder.linkProblems(links: links, disks: options.disks)
        let strayLinks = Set(problems.filter { $0.kind == .strayNestedLink }.compactMap { $0.path })

        // The user's skip list. A folder cannot be hidden by it and counted at the same time.
        let ignored = IgnoreList.read(options: options) ?? []
        var items: [String: ScanItem] = [:]
        let catalogCategories = ItemCategory.allCases.filter { category in catalog.entries.contains { $0.category == category } }
        let laterCategories: [ItemCategory] = [.alreadyMoved, .largeUnknown, .downloads, .leftovers, .projects, .duplicates]
            + (options.usesSystemTools ? [.simulators] : [])
        var pending = Set(catalogCategories + laterCategories)

        func sortedItems() -> [ScanItem] {
            return items.values.filter { !IgnoreList.isIgnored($0.path, in: ignored) }.sorted { first, second in
                if first.size.bytes != second.size.bytes {
                    return first.size.bytes > second.size.bytes
                }
                return first.title < second.title
            }
        }
        func finish(_ categories: [ItemCategory]) {
            pending.subtract(categories)
            onPartial?(ScanReport(disk: disk, items: sortedItems(), problems: problems), pending)
        }
        finish([])

        for category in catalogCategories {
            for item in catalogItems(catalog: catalog, options: options, strayLinks: strayLinks, category: category, progress: progress) {
                items[item.path] = item
            }
            finish([category])
        }
        for link in links where items[link.path] == nil && !strayLinks.contains(link.path) {
            if let item = movedItem(path: link.path, target: link.target, options: options, progress: progress) {
                items[item.path] = item
            }
        }
        finish([.alreadyMoved])
        for item in largeUnknownItems(catalog: catalog, options: options, progress: progress) {
            items[item.path] = item
        }
        for item in DownloadsScanner.items(options: options, progress: progress) where items[item.path] == nil {
            items[item.path] = item
        }
        finish([.downloads])
        // After Downloads, so an old download is not listed twice. A file inside a listed folder is taken out of its size.
        for item in LargeFileScanner.items(options: options, progress: progress) where items[item.path] == nil && !IgnoreList.isIgnored(item.path, in: ignored) {
            add(item, into: &items)
        }
        finish([.largeUnknown])
        // With a disk missing, its apps cannot be seen, so their data would look like leftovers.
        let leftovers = problems.contains { $0.kind == .diskNotMounted }
            ? [] : LeftoverScanner.items(catalog: catalog, options: options, progress: progress)
        for item in leftovers where !IgnoreList.isIgnored(item.path, in: ignored) {
            add(item, into: &items)
        }
        finish([.leftovers])
        for item in ProjectScanner.items(options: options, progress: progress) where !IgnoreList.isIgnored(item.path, in: ignored) {
            add(item, into: &items)
        }
        finish([.projects])

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
        finish([.simulators])
        // The slowest block, so it comes last: it reads whole files.
        for item in DuplicateScanner.items(options: options, ignored: ignored, progress: progress) {
            items[item.path] = item
        }
        finish([.duplicates])
        return ScanReport(disk: disk, items: sortedItems(), problems: problems)
    }

    /// Adds an item. One inside a listed folder (Containers, a whole project folder) is taken out of that folder's size,
    /// so the disk bar does not count it twice. A new item with the same path as a listed one replaces it.
    private static func add(_ item: ScanItem, into items: inout [String: ScanItem]) {
        if items[item.path] == nil {
            var folder = (item.path as NSString).deletingLastPathComponent
            while folder != "/" && !folder.isEmpty {
                if let parent = items[folder] {
                    let size = parent.size
                    items[folder] = parent.with(size: FolderSize(
                        bytes: max(0, size.bytes - item.size.bytes), isIncomplete: size.isIncomplete, newestChange: size.newestChange
                    ))
                    break
                }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        items[item.path] = item
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

    private static func catalogItems(catalog: Catalog, options: ScanOptions, strayLinks: Set<String>, category: ItemCategory, progress: Progress?) -> [ScanItem] {
        var items: [ScanItem] = []
        for entry in catalog.entries where entry.action != .never && entry.category == category {
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
