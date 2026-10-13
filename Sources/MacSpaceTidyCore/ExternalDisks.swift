import Foundation

/// Answers questions about paths on external disks under `/Volumes`.
public struct ExternalDisks: Sendable {
    public static let DEFAULT_ROOT = "/Volumes"
    /// exFAT and FAT have no Unix permissions, so apps break when their data lives there.
    public static let SUPPORTED_FILE_SYSTEMS: Set<String> = ["apfs", "hfs"]

    public let volumesRoot: String

    public init(volumesRoot: String = ExternalDisks.DEFAULT_ROOT) {
        self.volumesRoot = volumesRoot
    }

    public func isOnExternalDisk(_ path: String) -> Bool {
        return volumeRoot(of: path) != nil
    }

    /// `/Volumes/<name>` for a path on an external disk, else nil.
    public func volumeRoot(of path: String) -> String? {
        guard PathTools.isSameOrInside(path, folder: volumesRoot), path != volumesRoot else {
            return nil
        }
        let relative = path.dropFirst(volumesRoot.count + 1)
        guard let name = relative.split(separator: "/").first else {
            return nil
        }
        return (volumesRoot as NSString).appendingPathComponent(String(name))
    }

    // ponytail: a stale empty folder in /Volumes reads as "mounted". Compare device ids if that shows up.
    public func isMounted(_ path: String) -> Bool {
        guard let root = volumeRoot(of: path) else {
            return true
        }
        return PathTools.isDirectory(root)
    }

    public static func isSupported(fileSystem: String) -> Bool {
        return SUPPORTED_FILE_SYSTEMS.contains(fileSystem)
    }

    /// File system type name, like `apfs`, `hfs`, `exfat`, `msdos`.
    public static func fileSystem(of path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            return nil
        }
        return withUnsafeBytes(of: info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Nil when folders can be moved to `diskRoot`, else the reason why not.
    public func problem(with diskRoot: String) -> String? {
        guard isMounted(diskRoot), PathTools.isDirectory(diskRoot) else {
            return "The disk is not connected."
        }
        guard let fileSystem = ExternalDisks.fileSystem(of: diskRoot), ExternalDisks.isSupported(fileSystem: fileSystem) else {
            return "The disk format does not keep file permissions. Use APFS or Mac OS Extended."
        }
        guard access(diskRoot, W_OK) == 0 else {
            return "The disk is read-only."
        }
        return nil
    }

    /// Disks under the volumes root, except the internal one.
    public func choices(internalPath: String) -> [DiskChoice] {
        var internalInfo = stat()
        stat(internalPath, &internalInfo)
        var result: [DiskChoice] = []
        for path in PathTools.children(of: volumesRoot) {
            var info = stat()
            guard stat(path, &info) == 0, info.st_dev != internalInfo.st_dev, PathTools.isDirectory(path) else {
                continue
            }
            result.append(DiskChoice(
                path: path,
                name: (path as NSString).lastPathComponent,
                fileSystem: ExternalDisks.fileSystem(of: path) ?? "?",
                freeBytes: DiskSpace.read(path: path)?.freeBytes ?? 0,
                problem: problem(with: path)
            ))
        }
        return result
    }
}
