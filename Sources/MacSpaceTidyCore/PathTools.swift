import Foundation

public enum PathTools {
    private static let HOME_PREFIX = "~"

    public static func expand(_ path: String, home: String) -> String {
        guard path.hasPrefix(HOME_PREFIX) else {
            return path
        }
        return home + path.dropFirst(HOME_PREFIX.count)
    }

    public static func abbreviate(_ path: String, home: String) -> String {
        guard isSameOrInside(path, folder: home) else {
            return path
        }
        return HOME_PREFIX + path.dropFirst(home.count)
    }

    public static func isSameOrInside(_ path: String, folder: String) -> Bool {
        return path == folder || path.hasPrefix(folder + "/")
    }

    /// True when one path is the other path or contains it.
    public static func overlaps(_ first: String, _ second: String) -> Bool {
        return isSameOrInside(first, folder: second) || isSameOrInside(second, folder: first)
    }

    public static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    public static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    public static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// The link target as an absolute path, or nil when `path` is not a link.
    public static func linkTarget(_ path: String) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        if target.hasPrefix("/") {
            return target
        }
        let parent = (path as NSString).deletingLastPathComponent
        return ((parent as NSString).appendingPathComponent(target) as NSString).standardizingPath
    }

    /// The path with all links resolved, or the path itself when it does not exist.
    public static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else {
            return path
        }
        defer { free(real) }
        return String(cString: real)
    }

    public static func children(of folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.sorted().map { (folder as NSString).appendingPathComponent($0) }
    }
}
