import Foundation

/// Cleans a folder by deleting what is inside it. The folder itself stays, so links to it,
/// its permissions, and its attributes stay too. A plain file is deleted.
public enum FolderCleaner {
    private static let UNLOCK_TIMEOUT_SECONDS = 900.0

    public static func clean(_ path: String, mode: DeleteMode) throws {
        let isFolder = PathTools.isDirectory(path) && !PathTools.isSymlink(path)
        for target in isFolder ? PathTools.children(of: path) : [path] {
            try remove(target, mode: mode)
        }
    }

    public static func remove(_ path: String, mode: DeleteMode) throws {
        let url = URL(fileURLWithPath: path)
        switch mode {
        case .trash:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case .deleteNow:
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // Read-only trees (the Go module cache) and locked files refuse deletion until unlocked.
                makeWritable(path)
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func makeWritable(_ path: String) {
        _ = CommandRunner.run("/bin/chmod", ["-R", "u+w", path], timeoutSeconds: UNLOCK_TIMEOUT_SECONDS)
        _ = CommandRunner.run("/usr/bin/chflags", ["-R", "nouchg", path], timeoutSeconds: UNLOCK_TIMEOUT_SECONDS)
    }

    /// True when the folder is empty or the path is gone.
    public static func isClean(_ path: String) -> Bool {
        return !PathTools.exists(path) || (PathTools.isDirectory(path) && PathTools.children(of: path).isEmpty)
    }

    /// Root shell command that empties a folder the same way.
    public static func adminCommand(for path: String) -> String {
        return "/usr/bin/find \(AdminShell.shellQuoted(path)) -mindepth 1 -delete"
    }
}
