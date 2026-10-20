import Foundation
import Testing
@testable import MacSpaceTidyCore

struct LeftoverScannerTests {
    private static let BIG_BYTES = 2_000_000

    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            var options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: try temp.makeFolder("Volumes")), unknownParents: [], linkRoots: [home], usesSystemTools: false)
            options.appFolders = [try temp.makeFolder("Applications")]
            self.options = options
        }

        func install(_ app: String, id: String) throws {
            let folder = try temp.makeFolder("Applications/\(app).app/Contents")
            (["CFBundleIdentifier": id] as NSDictionary).write(toFile: folder + "/Info.plist", atomically: true)
        }

        func library(_ relative: String, bytes: Int = LeftoverScannerTests.BIG_BYTES) throws {
            try temp.makeFile("home/Library/\(relative)/blob", bytes: bytes)
        }
    }

    @Test func listsOnlyFoldersOfAppsThatAreNotInstalled() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.install("Kept", id: "com.vendor.Kept")
        try fixture.library("Application Support/com.vendor.Gone")
        try fixture.library("Caches/com.vendor.Gone")
        try fixture.library("Containers/com.vendor.Gone")
        try fixture.library("Group Containers/group.com.vendor.Gone")
        try fixture.library("Group Containers/ABCDE12345.com.vendor.Gone2")
        try fixture.library("Application Support/com.vendor.Kept")
        try fixture.library("Caches/com.vendor.Kept.ShipIt")
        try fixture.library("Caches/com.apple.Safari")
        try fixture.library("Caches/Homebrew")
        try fixture.library("Caches/com.vendor.Tiny", bytes: 10)

        let items = LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options)

        #expect(Set(items.map(\.title)) == [
            "~/Library/Application Support/com.vendor.Gone", "~/Library/Caches/com.vendor.Gone", "~/Library/Containers/com.vendor.Gone",
            "~/Library/Group Containers/group.com.vendor.Gone", "~/Library/Group Containers/ABCDE12345.com.vendor.Gone2",
        ])
        #expect(items.allSatisfy { $0.category == .leftovers && $0.action == .trashOnly && !$0.checkedByDefault && !$0.canMove })
    }

    @Test func aLeftoverInsideContainersIsTakenOutOfTheParentSize() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.library("Containers/com.vendor.Gone")
        try fixture.library("Containers/com.vendor.Live", bytes: 3_000_000)
        try fixture.install("Live", id: "com.vendor.Live")
        let containers = CatalogEntry(
            id: "containers", path: "~/Library/Containers", category: .cleanInApp, action: .cleanInApp, risk: .high,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test"
        )

        let report = try Scanner.scan(catalog: Catalog(entries: [containers]), options: fixture.options)

        let leftover = try #require(report.items(in: .leftovers).first)
        let parent = try #require(report.items.first { $0.title == "~/Library/Containers" })
        let whole = FolderSize.measure(path: fixture.temp.sub("home/Library/Containers")).bytes
        #expect(parent.size.bytes + leftover.size.bytes == whole)
    }

    @Test func trashesOnlyDirectEntriesOfTheLeftoverFolders() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let id = "com.mst-test.\(UUID().uuidString.prefix(8))"
        try fixture.library("Caches/\(id)")
        let trashedCopy = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash/\(id)")
        defer { try? FileManager.default.removeItem(atPath: trashedCopy) }
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: fixture.options, ownerCheck: { _ in nil })
        let item = try #require(LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options).first)
        let nested = item.with(size: item.size)
        let outsider = ScanItem(
            path: item.path + "/blob", title: "blob", catalogId: nil, category: .leftovers, action: .trashOnly, risk: .medium,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test", size: nested.size, linkTarget: nil
        )

        // The delete setting is "delete now", and the folder still must go to the Trash. A file inside it is refused.
        let result = optimizer.run(items: [outsider, item], mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.map(\.status) == [.skipped("Only entries of the Downloads folder and of the leftover folders can be trashed."), .done])
        #expect(!PathTools.exists(item.path))
        #expect(PathTools.exists(trashedCopy))
    }

    @Test func folderNamesAreMappedToBundleIds() {
        #expect(LeftoverScanner.appId(ofName: "com.vendor.App") == "com.vendor.App")
        #expect(LeftoverScanner.appId(ofName: "group.com.vendor.App") == "com.vendor.App")
        #expect(LeftoverScanner.appId(ofName: "ABCDE12345.com.vendor.App") == "com.vendor.App")
        #expect(LeftoverScanner.appId(ofName: "com.apple.Safari") == nil)
        #expect(LeftoverScanner.appId(ofName: "group.com.apple.notes") == nil)
        #expect(LeftoverScanner.appId(ofName: "Homebrew") == nil)
        #expect(LeftoverScanner.appId(ofName: "com.vendor") == nil)
        #expect(LeftoverScanner.appId(ofName: "08162DA9-B756-4855-91D8-04F4B7C9BBBB") == nil)
    }
}
