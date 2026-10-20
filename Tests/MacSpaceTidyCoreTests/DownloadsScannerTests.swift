import Foundation
import Testing
@testable import MacSpaceTidyCore

struct DownloadsScannerTests {
    private static let BIG_BYTES = 2_000_000
    private static let DAY: TimeInterval = 86_400

    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: try temp.makeFolder("Volumes")), unknownParents: [home], linkRoots: [home], usesSystemTools: false)
        }

        @discardableResult
        func download(_ name: String, daysOld: Double, bytes: Int = DownloadsScannerTests.BIG_BYTES) throws -> String {
            let path = try temp.makeFile("home/Downloads/\(name)", bytes: bytes)
            let date = Date().addingTimeInterval(-daysOld * DownloadsScannerTests.DAY)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
            return path
        }
    }

    @Test func listsOldEntriesWithTheRightAgeForTheirKind() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.download("old-installer.dmg", daysOld: 40)
        try fixture.download("young-installer.dmg", daysOld: 10)
        try fixture.download("old-video.mp4", daysOld: 100)
        try fixture.download("middle-video.mp4", daysOld: 50)
        try fixture.download("tiny-old.txt", daysOld: 500, bytes: 100)
        try fixture.download(".DS_Store", daysOld: 500)
        try fixture.temp.makeLink("home/Downloads/Downloads", to: fixture.temp.sub("Volumes/SSD"))

        let items = DownloadsScanner.items(options: fixture.options)

        #expect(Set(items.map(\.title)) == ["~/Downloads/old-installer.dmg", "~/Downloads/old-video.mp4"])
        #expect(items.allSatisfy { $0.category == .downloads && $0.action == .trashOnly && !$0.checkedByDefault && $0.canMove })
    }

    @Test func foldersAreListedAsOneEntryAndAgeFollowsTheNewestFileInside() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.download("project/old.bin", daysOld: 200)
        try fixture.download("project/new.bin", daysOld: 3)
        try fixture.download("archive/old.bin", daysOld: 200)
        // A real old folder has an old modification date too; a folder made just now would look new.
        let old = Date().addingTimeInterval(-200 * DownloadsScannerTests.DAY)
        for folder in ["project", "archive"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: fixture.temp.sub("home/Downloads/\(folder)"))
        }

        let items = DownloadsScanner.items(options: fixture.options)

        #expect(items.map(\.title) == ["~/Downloads/archive"])
    }

    @Test func downloadsIsNotListedAsAnUnknownFolder() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.download("old-video.mp4", daysOld: 100, bytes: 5_000_000)
        var options = fixture.options
        options.largeUnknownBytes = 1_000_000

        let report = try Scanner.scan(catalog: Catalog(entries: []), options: options)

        #expect(report.items(in: .largeUnknown).isEmpty)
        #expect(report.items(in: .downloads).count == 1)
    }

    @Test func trashesOnlyDirectEntriesOfDownloadsAndAlwaysToTheTrash() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let name = "mst-test-\(UUID().uuidString).bin"
        try fixture.download(name, daysOld: 100)
        try fixture.temp.makeFile("home/Documents/keep.bin", bytes: 10)
        let trashedCopy = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash/\(name)")
        defer { try? FileManager.default.removeItem(atPath: trashedCopy) }
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: fixture.options, ownerCheck: { _ in nil })
        let item = try #require(DownloadsScanner.items(options: fixture.options).first)
        let outsider = ScanItem(
            path: fixture.temp.sub("home/Documents/keep.bin"), title: "keep", catalogId: nil, category: .downloads, action: .trashOnly,
            risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize(bytes: 1, isIncomplete: false), linkTarget: nil
        )

        // The delete setting is "delete now", and the file still must go to the Trash.
        let result = optimizer.run(items: [item, outsider], mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.map(\.status) == [.done, .skipped("Only entries of the Downloads folder, of the leftover folders, and build folders of projects can be trashed.")])
        #expect(!PathTools.exists(item.path))
        #expect(PathTools.exists(trashedCopy))
        #expect(PathTools.exists(fixture.temp.sub("home/Documents/keep.bin")))
    }

    @Test func installersAreRecognizedByExtension() {
        #expect(DownloadsScanner.kind(ofName: "App.DMG") == .installer)
        #expect(DownloadsScanner.kind(ofName: "data.zip") == .archive)
        #expect(DownloadsScanner.kind(ofName: "movie.mp4") == .other)
        #expect(DownloadsScanner.ageThresholdDays(for: .installer) < DownloadsScanner.ageThresholdDays(for: .other))
    }
}
