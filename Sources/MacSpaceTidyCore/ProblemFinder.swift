import Foundation

public enum ProblemFinder {
    /// Chromium apps keep lock files as links to non-existing targets. They are normal.
    public static let CHROMIUM_LOCK_NAMES: Set<String> = ["SingletonLock", "SingletonCookie", "SingletonSocket"]
    public static let LOW_FREE_FRACTION = 0.10
    public static let LOW_FREE_BYTES: Int64 = 20_000_000_000

    public static func linkProblems(links: [LinkInfo], disks: ExternalDisks) -> [Problem] {
        var problems: [Problem] = []
        for link in links {
            if let problem = problem(for: link, disks: disks) {
                problems.append(problem)
            }
        }
        return problems
    }

    public static func freeSpaceProblem(disk: DiskSpace) -> Problem? {
        let freeFraction = Double(disk.freeBytes) / Double(max(disk.totalBytes, 1))
        guard freeFraction < LOW_FREE_FRACTION || disk.freeBytes < LOW_FREE_BYTES else {
            return nil
        }
        return Problem(
            kind: .lowFreeSpace,
            path: nil,
            detail: "Low free space. macOS may run out of swap and restart."
        )
    }

    public static func snapshotProblem(snapshotCount: Int) -> Problem? {
        guard snapshotCount > 0 else {
            return nil
        }
        return Problem(
            kind: .timeMachineSnapshots,
            path: nil,
            detail: "\(snapshotCount) local Time Machine snapshot(s). They can hold space after you delete files."
        )
    }

    private static func problem(for link: LinkInfo, disks: ExternalDisks) -> Problem? {
        if !disks.isMounted(link.target) {
            let disk = disks.volumeRoot(of: link.target) ?? link.target
            return Problem(kind: .diskNotMounted, path: link.path, detail: "Points to \(disk), which is not connected.")
        }
        if isStrayNested(link) {
            return Problem(
                kind: .strayNestedLink,
                path: link.path,
                detail: "Link inside a folder with the same name. A move did not finish. Data at \(link.target) stays."
            )
        }
        let name = (link.path as NSString).lastPathComponent
        if !PathTools.exists(link.target) && !CHROMIUM_LOCK_NAMES.contains(name) {
            return Problem(kind: .brokenLink, path: link.path, detail: "Points to \(link.target), which does not exist.")
        }
        return nil
    }

    /// `ln -s <dest> <src>` when `<src>` already exists creates `<src>/<name>` instead of replacing `<src>`.
    private static func isStrayNested(_ link: LinkInfo) -> Bool {
        let name = (link.path as NSString).lastPathComponent
        let parentName = ((link.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let targetName = (link.target as NSString).lastPathComponent
        return name == parentName && name == targetName
    }
}
