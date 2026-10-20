import Foundation

/// Paths the user does not want to see or clean again. One path per line in `ignore.txt` (see `PathListFile`).
/// The user removes a line to undo it.
public enum IgnoreList {
    /// Absolute paths. Empty when there is no file. Nil when the file exists but cannot be read:
    /// a clean must then refuse, because it cannot know what the user wanted to keep.
    public static func read(options: ScanOptions) -> [String]? {
        return PathListFile.read(at: options.ignorePath, home: options.home)
    }

    /// True for a listed path and for everything inside it.
    public static func isIgnored(_ path: String, in list: [String]) -> Bool {
        return list.contains { PathTools.isSameOrInside(path, folder: $0) }
    }

    public static func add(_ path: String, options: ScanOptions) throws {
        try PathListFile.add(path, at: options.ignorePath, home: options.home)
    }
}
