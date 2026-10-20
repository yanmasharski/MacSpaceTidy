import Foundation

/// A text file with one path per line. `~` is the home folder and `#` starts a comment.
/// Used for the ignore list and the project folders list, so the user can edit them by hand.
enum PathListFile {
    /// Absolute paths. Empty when there is no file. Nil when the file exists but cannot be read.
    static func read(at path: String, home: String) -> [String]? {
        guard PathTools.exists(path) else {
            return []
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { PathTools.expand($0, home: home) }
    }

    static func add(_ entry: String, at path: String, home: String) throws {
        if (read(at: path, home: home) ?? []).contains(entry) {
            return
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + separator + PathTools.abbreviate(entry, home: home) + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
