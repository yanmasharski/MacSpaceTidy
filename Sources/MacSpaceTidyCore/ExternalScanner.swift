import Foundation

/// Second, slow scan of folders already on external disks. Runs after the main scan.
/// Measures moved folders and finds space to free there: caches inside moved folders, and copies nothing links to.
public enum ExternalScanner {
    public enum Mode: Sendable {
        /// Fast: only sizes from the size cache. Items never measured before keep size 0.
        case cachedOnly
        /// Slow: measure now, update the size cache.
        case fresh
    }

    private static let CACHE_REASON = "Cache on the external disk. Cleaning deletes what is inside; the folder and its link stay."
    private static let ORPHAN_REASON = "Copy on the external disk that nothing links to (for example after Move back). Delete it when you no longer need it."

    public static func scan(
        report: ScanReport, catalog: Catalog, options: ScanOptions, mode: Mode = .fresh, progress: Scanner.Progress? = nil
    ) -> ScanReport {
        let measurer = Measurer(mode: mode, cache: SizeCache.load(from: options.sizeCachePath))
        var items = report.items.filter { $0.category != .external }
        var cleanups: [ScanItem] = []
        let deleteEntriesByPath = deleteEntries(catalog: catalog, home: options.home)

        // Only the targets of known links are read, never the whole disk.
        for (index, moved) in items.enumerated() where moved.category == .alreadyMoved {
            guard let target = moved.linkTarget, options.disks.isMounted(target) else {
                continue
            }
            progress?(moved.title)
            let measured = moved.with(size: measurer.size(of: target) ?? moved.size)
            items[index] = measured
            cleanups += cacheCleanups(moved: measured, target: target, entriesByPath: deleteEntriesByPath, options: options, measurer: measurer)
        }
        let linkedTargets = Set(items.compactMap(\.linkTarget))
        cleanups += orphanCleanups(linkedTargets: linkedTargets, options: options, measurer: measurer, progress: progress)
        if mode == .fresh {
            try? measurer.cache.save(to: options.sizeCachePath)
        }

        let sorted = (items + cleanups.filter { $0.size.bytes >= options.minChildItemBytes }).sorted { first, second in
            if first.size.bytes != second.size.bytes {
                return first.size.bytes > second.size.bytes
            }
            return first.title < second.title
        }
        return ScanReport(disk: report.disk, items: sorted, problems: report.problems, externalDisks: diskUsage(items: items, options: options))
    }

    /// Every concrete path of every delete entry, so a moved link can be matched to its rule.
    private static func deleteEntries(catalog: Catalog, home: String) -> [String: CatalogEntry] {
        var result: [String: CatalogEntry] = [:]
        for entry in catalog.entries where entry.action == .delete && !entry.needsAdmin {
            for path in Scanner.expandedPaths(of: entry, catalog: catalog, home: home) {
                result[path] = entry
            }
        }
        return result
    }

    private static func cacheCleanups(
        moved: ScanItem, target: String, entriesByPath: [String: CatalogEntry], options: ScanOptions, measurer: Measurer
    ) -> [ScanItem] {
        // The moved folder is itself a cache (like ~/.cache/uv): empty it, keep the link.
        if let entry = entriesByPath[moved.path] {
            return [cleanup(path: moved.path, title: moved.title, size: moved.size, ownerApps: entry.ownerApps, reason: CACHE_REASON)]
        }
        // A cache inside the moved folder (like DerivedData inside a moved Xcode folder).
        var result: [ScanItem] = []
        for (path, entry) in entriesByPath where path.hasPrefix(moved.path + "/") {
            let resolved = target + path.dropFirst(moved.path.count)
            guard PathTools.isDirectory(resolved), !PathTools.isSymlink(resolved), let size = measurer.size(of: resolved) else {
                continue
            }
            result.append(cleanup(
                path: resolved,
                title: PathTools.abbreviate(path, home: options.home),
                size: size,
                ownerApps: entry.ownerApps,
                reason: CACHE_REASON
            ))
        }
        return result
    }

    private static func orphanCleanups(
        linkedTargets: Set<String>, options: ScanOptions, measurer: Measurer, progress: Scanner.Progress?
    ) -> [ScanItem] {
        var copies = Set<String>()
        for record in MoveJournal.read(from: options.journalPath) {
            copies.insert(record.kind == MoveJournal.KIND_MOVE ? record.destination : record.source)
        }
        var result: [ScanItem] = []
        for copy in copies.sorted() where !linkedTargets.contains(copy) && PathTools.isDirectory(copy) && !PathTools.isSymlink(copy) {
            progress?(copy)
            guard let size = measurer.size(of: copy) else {
                continue
            }
            result.append(cleanup(
                path: copy, title: copy, size: size, ownerApps: [], reason: ORPHAN_REASON,
                action: .deleteExternalCopy, risk: .medium
            ))
        }
        return result
    }

    private static func cleanup(
        path: String, title: String, size: FolderSize, ownerApps: [String], reason: String,
        action: ItemAction = .cleanExternal, risk: Risk = .low
    ) -> ScanItem {
        return ScanItem(
            path: path, title: title, catalogId: nil, category: .external, action: action, risk: risk,
            checkedByDefault: false, needsAdmin: false, ownerApps: ownerApps, reason: reason, size: size, linkTarget: nil
        )
    }

    private static func diskUsage(items: [ScanItem], options: ScanOptions) -> [ExternalDiskUsage] {
        var movedBytesByRoot: [String: Int64] = [:]
        for item in items where item.category == .alreadyMoved {
            if let target = item.linkTarget, let root = options.disks.volumeRoot(of: target), options.disks.isMounted(target) {
                movedBytesByRoot[root, default: 0] += item.size.bytes
            }
        }
        return movedBytesByRoot.keys.sorted().compactMap { root in
            DiskSpace.read(path: root).map { ExternalDiskUsage(root: root, space: $0, movedBytes: movedBytesByRoot[root] ?? 0) }
        }
    }
}

/// Gives a size from the cache, or measures it and remembers it, depending on the mode.
private final class Measurer {
    private let mode: ExternalScanner.Mode
    private(set) var cache: SizeCache

    init(mode: ExternalScanner.Mode, cache: SizeCache) {
        self.mode = mode
        self.cache = cache
    }

    /// Nil in cache-only mode when the path was never measured.
    func size(of path: String) -> FolderSize? {
        switch mode {
        case .cachedOnly:
            return cache.size(for: path)
        case .fresh:
            let size = FolderSize.measure(path: path)
            cache.store(size, for: path)
            return size
        }
    }
}
