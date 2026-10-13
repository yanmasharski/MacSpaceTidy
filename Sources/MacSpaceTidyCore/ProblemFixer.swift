import Foundation

public enum ProblemFixer {
    private static let DELETE_SNAPSHOTS = "/usr/bin/tmutil deletelocalsnapshots /"

    /// Removes the link only. The data it points to stays.
    public static func removeLink(at path: String) throws {
        guard PathTools.isSymlink(path) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.removeItem(atPath: path)
    }

    /// Returns nil on success, else an error text.
    public static func deleteLocalSnapshots(adminRunner: Optimizer.AdminRunner = AdminShell.run) -> String? {
        return adminRunner([DELETE_SNAPSHOTS])
    }
}
