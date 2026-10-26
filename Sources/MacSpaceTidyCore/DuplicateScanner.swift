import CryptoKit
import Foundation

/// One of several identical files.
public struct DuplicateCopy: Sendable, Equatable {
    public let path: String
    public let bytes: Int64
    public let modified: Date?
    /// Name of the external disk, or nil for this Mac.
    public let diskName: String?
}

/// Finds identical files by content: the same size, then the same start and end, then the same SHA-256 of everything.
/// A group is one item. The user picks the copy that stays; the others go to the Trash.
/// Safety: a copy is trashed only when the kept copy still exists and its full hash is the same, checked right before.
/// Links, hard links, hidden files, packages, git repositories, and the tool's own folder on a disk are left out.
public enum DuplicateScanner {
    private static let SAMPLE_BYTES = 1 << 20
    private static let CHUNK_BYTES = 1 << 20
    private static let MAX_DEPTH = 12
    private static let PROGRESS_DEPTH = 2
    private static let KEYS: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
    ]

    private struct Candidate {
        let path: String
        let modified: Date?
    }

    /// Folders searched: the personal folders on this Mac, plus the external disks the user allowed.
    public static func roots(options: ScanOptions) -> [String] {
        return LargeFileScanner.searchedRoots(options: options)
    }

    public static func items(options: ScanOptions, ignored: [String] = [], progress: Scanner.Progress? = nil) -> [ScanItem] {
        var bySize: [Int64: [Candidate]] = [:]
        for root in roots(options: options) {
            collect(root: root, options: options, progress: progress, into: &bySize)
        }
        var result: [ScanItem] = []
        for (size, candidates) in bySize where candidates.count > 1 {
            for group in identicalGroups(candidates, size: size, progress: progress, options: options) {
                let copies = group.0.filter { !IgnoreList.isIgnored($0.path, in: ignored) }
                if copies.count > 1 {
                    result.append(item(copies: copies, hash: group.1))
                }
            }
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    /// Nil when the copy may go to the Trash now, else the reason why not.
    public static func refusal(_ item: ScanItem, options: ScanOptions) -> String? {
        guard let keeper = item.keeperPath else {
            return "No copy to keep is known. Scan again."
        }
        let path = item.path
        guard isRegularFile(path), isRegularFile(keeper) else {
            return "A copy is gone or is not a plain file. Scan again."
        }
        guard let first = fileID(path), let second = fileID(keeper), first != second else {
            return "Both names are the same file."
        }
        guard isSearchedLocation(path, options: options) else {
            return "Outside the folders MacSpaceTidy searches for duplicates."
        }
        guard fileSize(path) == fileSize(keeper), let hash = fullHash(path), hash == fullHash(keeper) else {
            return "The copies are not identical now. Scan again."
        }
        return nil
    }

    private static func isSearchedLocation(_ path: String, options: ScanOptions) -> Bool {
        return LargeFileScanner.isSearched(path, options: options)
    }

    // MARK: Search

    private static func collect(root: String, options: ScanOptions, progress: Scanner.Progress?, into bySize: inout [Int64: [Candidate]]) {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root), includingPropertiesForKeys: KEYS, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(KEYS)) else {
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
            } else if values.isDirectory == true {
                if values.isPackage == true || enumerator.level > MAX_DEPTH || LargeFileScanner.SKIPPED_FOLDERS.contains(url.lastPathComponent)
                    || PathTools.isDirectory(url.path + "/.git") {
                    enumerator.skipDescendants()
                } else if enumerator.level <= PROGRESS_DEPTH {
                    progress?("Duplicates: " + PathTools.abbreviate(url.path, home: options.home))
                }
            } else if values.isRegularFile == true, let size = values.fileSize, Int64(size) >= options.duplicateMinBytes {
                bySize[Int64(size), default: []].append(Candidate(path: url.path, modified: values.contentModificationDate))
            }
        }
    }

    /// Groups of really identical files among candidates of one size, each with its full hash.
    private static func identicalGroups(
        _ candidates: [Candidate], size: Int64, progress: Scanner.Progress?, options: ScanOptions
    ) -> [([DuplicateCopy], String)] {
        // The same file under two names (hard link) is not a duplicate: deleting a name frees nothing.
        var seenIDs = Set<FileID>()
        let distinct = candidates.filter { candidate in
            fileID(candidate.path).map { seenIDs.insert($0).inserted } ?? false
        }
        var sampled: [String: [Candidate]] = [:]
        for candidate in distinct {
            progress?("Comparing " + PathTools.abbreviate(candidate.path, home: options.home))
            if let key = sampleHash(candidate.path, size: size) {
                sampled[key, default: []].append(candidate)
            }
        }
        var groups: [([DuplicateCopy], String)] = []
        for sameSample in sampled.values where sameSample.count > 1 {
            var full: [String: [Candidate]] = [:]
            for candidate in sameSample {
                if let key = fullHash(candidate.path) {
                    full[key, default: []].append(candidate)
                }
            }
            for (hash, same) in full where same.count > 1 {
                groups.append((same.map { copy($0, size: size, options: options) }, hash))
            }
        }
        return groups
    }

    private static func copy(_ candidate: Candidate, size: Int64, options: ScanOptions) -> DuplicateCopy {
        let disk = options.disks.volumeRoot(of: candidate.path).map { ($0 as NSString).lastPathComponent }
        return DuplicateCopy(path: candidate.path, bytes: size, modified: candidate.modified, diskName: disk)
    }

    /// The suggested original comes first: the oldest copy, then the shortest path.
    private static func item(copies unsorted: [DuplicateCopy], hash: String) -> ScanItem {
        let copies = unsorted.sorted { first, second in
            if first.modified != second.modified {
                return (first.modified ?? .distantFuture) < (second.modified ?? .distantFuture)
            }
            return first.path.count != second.path.count ? first.path.count < second.path.count : first.path < second.path
        }
        let bytes = copies[0].bytes
        let name = (copies[0].path as NSString).lastPathComponent
        return ScanItem(
            path: "duplicates:" + hash, title: "\(name) — \(copies.count) copies", catalogId: nil, category: .duplicates,
            action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [],
            reason: "\(copies.count) identical copies. Pick the one to keep. The others go to the Trash.",
            size: FolderSize(bytes: bytes * Int64(copies.count - 1), isIncomplete: false, newestChange: copies.compactMap(\.modified).max()),
            linkTarget: nil, duplicateCopies: copies
        )
    }

    // MARK: Files and hashes

    private struct FileID: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private static func fileID(_ path: String) -> FileID? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return nil
        }
        return FileID(device: info.st_dev, inode: UInt64(info.st_ino))
    }

    private static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private static func fileSize(_ path: String) -> Int64? {
        var info = stat()
        return lstat(path, &info) == 0 ? Int64(info.st_size) : nil
    }

    /// First and last megabyte plus the size. Cheap, and it rules out most files of the same size.
    private static func sampleHash(_ path: String, size: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            hasher.update(data: try handle.read(upToCount: SAMPLE_BYTES) ?? Data())
            if size > Int64(SAMPLE_BYTES) {
                try handle.seek(toOffset: UInt64(max(size - Int64(SAMPLE_BYTES), 0)))
                hasher.update(data: try handle.read(upToCount: SAMPLE_BYTES) ?? Data())
            }
        } catch {
            return nil
        }
        return hex(hasher.finalize())
    }

    static func fullHash(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: CHUNK_BYTES), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
