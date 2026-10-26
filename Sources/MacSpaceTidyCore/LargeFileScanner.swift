import Foundation

/// Finds single big files of yours (videos, disk images, archives) in the usual personal folders.
/// They are your own data, so they are never checked by default and always go to the Trash.
/// Moving to an external disk is the alternative. Files inside a git repository are left alone.
public enum LargeFileScanner {
    private static let FOLDERS = ["Desktop", "Documents", "Movies", "Music", "Pictures", "Downloads"]
    /// Never searched: backups, trash folders of disks, and the tool's own folder (it holds copies of moved folders).
    static let SKIPPED_FOLDERS: Set<String> = ["Backups.backupdb", ".Trashes", Mover.FOLDER_NAME]
    private static let MAX_DEPTH = 8
    private static let PROGRESS_DEPTH = 2
    private static let KEYS: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Existing folders on the internal disk. A link (a folder already moved) is not searched.
    public static func roots(options: ScanOptions) -> [String] {
        return FOLDERS.map { (options.home as NSString).appendingPathComponent($0) }.filter {
            PathTools.isDirectory($0) && !PathTools.isSymlink($0) && !options.disks.isOnExternalDisk(PathTools.resolved($0))
        }
    }

    /// The personal folders on this Mac, plus the external disks the user chose.
    public static func searchedRoots(options: ScanOptions) -> [String] {
        return roots(options: options) + options.extraVolumes.filter { PathTools.isDirectory($0) }
    }

    /// True for a path inside a searched folder, outside git repositories and the skipped folders.
    static func isSearched(_ path: String, options: ScanOptions) -> Bool {
        return searchedRoots(options: options).contains { root in
            PathTools.isSameOrInside(path, folder: root) && path != root && !isInsideRepository(path, root: root)
                && !path.dropFirst(root.count).split(separator: "/").contains { SKIPPED_FOLDERS.contains(String($0)) }
        }
    }

    public static func items(options: ScanOptions, progress: Scanner.Progress? = nil) -> [ScanItem] {
        var result: [ScanItem] = []
        for root in searchedRoots(options: options) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: KEYS, options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(KEYS)) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                } else if values.isDirectory == true {
                    if values.isPackage == true || enumerator.level > MAX_DEPTH || SKIPPED_FOLDERS.contains(url.lastPathComponent)
                        || PathTools.isDirectory(url.path + "/.git") {
                        enumerator.skipDescendants()
                    } else if enumerator.level <= PROGRESS_DEPTH {
                        progress?(PathTools.abbreviate(url.path, home: options.home))
                    }
                } else if values.isRegularFile == true, let bytes = values.totalFileAllocatedSize, Int64(bytes) >= options.largeFileBytes {
                    result.append(item(path: url.path, bytes: Int64(bytes), changed: values.contentModificationDate, options: options))
                }
            }
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    /// True for a big regular file inside one of the searched folders and outside any git repository.
    public static func canTrash(_ path: String, options: ScanOptions) -> Bool {
        guard !PathTools.isSymlink(path), PathTools.exists(path), !PathTools.isDirectory(path),
              let bytes = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize,
              Int64(bytes) >= options.largeFileBytes else {
            return false
        }
        return isSearched(path, options: options)
    }

    /// True when a folder between the file and `root` holds a `.git` folder.
    static func isInsideRepository(_ path: String, root: String) -> Bool {
        var folder = (path as NSString).deletingLastPathComponent
        while PathTools.isSameOrInside(folder, folder: root) {
            if PathTools.isDirectory(folder + "/.git") {
                return true
            }
            if folder == root {
                break
            }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return false
    }

    private static func item(path: String, bytes: Int64, changed: Date?, options: ScanOptions) -> ScanItem {
        let when = changed.map { " Last changed \(RelativeTime.ago($0))." } ?? ""
        return ScanItem(
            path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .largeUnknown,
            action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [],
            reason: "A large file of yours. Check what it is first." + when,
            size: FolderSize(bytes: bytes, isIncomplete: false, newestChange: changed), linkTarget: nil,
            canMove: options.disks.volumeRoot(of: path) == nil
        )
    }
}
