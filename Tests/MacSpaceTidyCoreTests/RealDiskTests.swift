import Foundation
import Testing
@testable import MacSpaceTidyCore

/// Moves a small temp folder to a real external disk and back.
/// Off by default. Run: MST_REAL_DISK=/Volumes/<disk> swift test --filter RealDiskTests
struct RealDiskTests {
    private static let DISK_VARIABLE = "MST_REAL_DISK"
    private static let diskRoot = ProcessInfo.processInfo.environment[DISK_VARIABLE]

    @Test(.enabled(if: diskRoot != nil))
    func movesToRealDiskAndBack() throws {
        let diskRoot = try #require(RealDiskTests.diskRoot)
        let temp = try TempFolder()
        defer { temp.remove() }
        let home = try temp.makeFolder("home")
        try temp.makeFile("home/AppData/\u{0439}.txt", bytes: 5000)
        try temp.makeFile("home/AppData/sub/b.bin", bytes: 70000)
        let source = temp.sub("home/AppData")
        let destination = Mover.destination(for: source, diskRoot: diskRoot)
        let toolFolder = (diskRoot as NSString).appendingPathComponent(Mover.FOLDER_NAME)
        defer {
            // Remove the test copy, then its empty parent folders up to and including the tool folder.
            var folder = toolFolder + temp.path
            try? FileManager.default.removeItem(atPath: folder)
            while folder != toolFolder && PathTools.isSameOrInside(folder, folder: toolFolder) {
                folder = (folder as NSString).deletingLastPathComponent
                rmdir(folder)
            }
        }
        let options = ScanOptions(home: home, disks: ExternalDisks(), unknownParents: [], linkRoots: [], usesSystemTools: false)
        let mover = Mover(catalog: Catalog(entries: []), options: options)
        let item = ScanItem(
            path: source, title: "AppData", catalogId: nil, category: .apps, action: .move, risk: .low,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize.measure(path: source), linkTarget: nil
        )
        let before = TreeSummary.make(path: source)

        #expect(mover.move(item, diskRoot: diskRoot) == .done)
        #expect(PathTools.linkTarget(source) == destination)
        #expect(mover.moveBack(item.with(action: .moveBack)) == .done)
        #expect(!PathTools.isSymlink(source))
        #expect(TreeSummary.make(path: source) == before)
    }
}
