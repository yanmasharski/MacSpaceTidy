import Foundation

/// Allocated size on disk, like `du`. Does not follow links, stays on one volume,
/// counts a hard-linked file once.
public struct FolderSize: Sendable, Equatable {
    private struct FileIdentity: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private static let BLOCK_BYTES: Int64 = 512

    public let bytes: Int64
    /// Some entries could not be read (for example without Full Disk Access).
    public let isIncomplete: Bool
    /// Newest modification date inside. A hint for "not used for months".
    public let newestChange: Date?
    /// Set when the number comes from an earlier scan (the size cache), not from this one.
    public let cachedAt: Date?

    public init(bytes: Int64, isIncomplete: Bool, newestChange: Date? = nil, cachedAt: Date? = nil) {
        self.bytes = bytes
        self.isIncomplete = isIncomplete
        self.newestChange = newestChange
        self.cachedAt = cachedAt
    }

    // MARK: Fast measure

    private static let PARALLEL_DEPTH = 2
    private static let OPEN_FLAGS = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    private struct Totals {
        var bytes: Int64 = 0
        var newestSeconds = 0
        var isIncomplete = false

        init(isIncomplete: Bool = false) {
            self.isIncomplete = isIncomplete
        }

        mutating func add(_ other: Totals) {
            bytes += other.bytes
            newestSeconds = max(newestSeconds, other.newestSeconds)
            isIncomplete = isIncomplete || other.isIncomplete
        }
    }

    /// A file with several hard links is counted once, also across threads.
    private final class HardLinks: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<FileIdentity>()

        func isFirstVisit(device: Int32, fileID: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return seen.insert(FileIdentity(device: device, inode: fileID)).inserted
        }
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var totals = Totals()

        func add(_ other: Totals) {
            lock.lock()
            totals.add(other)
            lock.unlock()
        }

        var value: Totals {
            lock.lock()
            defer { lock.unlock() }
            return totals
        }
    }

    /// Allocated size on disk, like `du`. Reads whole folders with `getattrlistbulk`, and the first two
    /// levels of subfolders in parallel. Does not follow links, stays on one volume.
    public static func measure(path: String) -> FolderSize {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return FolderSize(bytes: 0, isIncomplete: true)
        }
        if (info.st_mode & S_IFMT) != S_IFDIR && (info.st_mode & S_IFMT) != S_IFLNK {
            return FolderSize(bytes: Int64(info.st_blocks) * BLOCK_BYTES, isIncomplete: false, newestChange: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)))
        }
        // A link as the root (a moved folder) is read through the link.
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            return FolderSize(bytes: 0, isIncomplete: true)
        }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0 else {
            return FolderSize(bytes: 0, isIncomplete: true)
        }
        var totals = walk(descriptor: descriptor, device: info.st_dev, depth: 0, links: HardLinks(), reader: BulkDirectoryReader())
        totals.newestSeconds = max(totals.newestSeconds, info.st_mtimespec.tv_sec)
        let newestChange = totals.newestSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(totals.newestSeconds)) : nil
        return FolderSize(bytes: totals.bytes, isIncomplete: totals.isIncomplete, newestChange: newestChange)
    }

    private static func walk(descriptor: Int32, device: Int32, depth: Int, links: HardLinks, reader: BulkDirectoryReader) -> Totals {
        var totals = Totals()
        var subfolders: [String] = []
        let isRead = reader.forEachEntry(of: descriptor) { entry in
            totals.newestSeconds = max(totals.newestSeconds, entry.modifiedSeconds)
            if entry.hasError {
                totals.isIncomplete = true
            } else if entry.isDirectory {
                subfolders.append(entry.name)
            } else if entry.linkCount <= 1 || links.isFirstVisit(device: device, fileID: entry.fileID) {
                totals.bytes += entry.allocatedBytes
            }
        }
        if !isRead {
            totals.isIncomplete = true
        }

        func measureSubfolder(_ name: String, reader: BulkDirectoryReader) -> Totals {
            let child = openat(descriptor, name, OPEN_FLAGS)
            guard child >= 0 else {
                return Totals(isIncomplete: true)
            }
            defer { close(child) }
            var info = stat()
            // Another device is a mount point (like another disk). Skip it, as `du -x` does.
            guard fstat(child, &info) == 0, info.st_dev == device else {
                return Totals()
            }
            return walk(descriptor: child, device: device, depth: depth + 1, links: links, reader: reader)
        }

        if depth < PARALLEL_DEPTH && subfolders.count > 1 {
            let results = Results()
            let names = subfolders
            DispatchQueue.concurrentPerform(iterations: names.count) { index in
                results.add(measureSubfolder(names[index], reader: BulkDirectoryReader()))
            }
            totals.add(results.value)
        } else {
            for name in subfolders {
                totals.add(measureSubfolder(name, reader: reader))
            }
        }
        return totals
    }
}
