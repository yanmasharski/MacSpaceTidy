import Foundation

/// Paths the user does not want to see or clean again. One path per line in `ignore.txt`;
/// `~` is the home folder and `#` starts a comment. The user removes a line to undo it.
public enum IgnoreList {
    /// Absolute paths. Empty when there is no file. Nil when the file exists but cannot be read:
    /// a clean must then refuse, because it cannot know what the user wanted to keep.
    public static func read(options: ScanOptions) -> [String]? {
        guard PathTools.exists(options.ignorePath) else {
            return []
        }
        guard let text = try? String(contentsOfFile: options.ignorePath, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { PathTools.expand($0, home: options.home) }
    }

    /// True for a listed path and for everything inside it.
    public static func isIgnored(_ path: String, in list: [String]) -> Bool {
        return list.contains { PathTools.isSameOrInside(path, folder: $0) }
    }

    public static func add(_ path: String, options: ScanOptions) throws {
        let line = PathTools.abbreviate(path, home: options.home)
        if (read(options: options) ?? []).contains(path) {
            return
        }
        try FileManager.default.createDirectory(atPath: (options.ignorePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let existing = (try? String(contentsOfFile: options.ignorePath, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + separator + line + "\n").write(toFile: options.ignorePath, atomically: true, encoding: .utf8)
    }
}
