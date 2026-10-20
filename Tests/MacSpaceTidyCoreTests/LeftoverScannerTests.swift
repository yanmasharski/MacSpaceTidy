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

    @Test func foldersOfApplicationSupportAreJudgedByTheNameOfInstalledApps() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let big = 21_000_000
        try fixture.install("Kept Tool", id: "com.vendor.KeptTool")
        try fixture.install("Google Chrome", id: "com.google.Chrome")
        try fixture.install("ChatGPT", id: "com.openai.codex")
        try fixture.install("Epic Games Launcher", id: "com.epicgames.EpicGamesLauncher")
        for name in ["Kept Tool", "Google", "vendor", "Codex", "Epic", "Chromium", "MobileSync", "Small Leftover", "com.apple.wallpaper"] {
            try fixture.library("Application Support/\(name)", bytes: name == "Small Leftover" ? 5_000_000 : big)
        }
        try fixture.library("Caches/Chromium", bytes: big)

        let items = LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options)

        // Only Chromium: the others match an app name or its vendor, belong to macOS, or are too small to judge by name.
        #expect(items.map(\.title) == ["~/Library/Application Support/Chromium"])
        #expect(items.allSatisfy { $0.risk == .high && !$0.checkedByDefault && $0.action == .trashOnly })
    }

    @Test func aWinePrefixIsALeftoverOnlyWhenWineIsNotInstalled() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.temp.makeFile("home/.wine/system.reg", bytes: LeftoverScannerTests.BIG_BYTES)
        let catalog = Catalog(entries: [])

        #expect(LeftoverScanner.items(catalog: catalog, options: fixture.options).map(\.title) == ["~/.wine"])
        try fixture.install("Wine Stable", id: "org.winehq.wine-stable")
        #expect(LeftoverScanner.items(catalog: catalog, options: fixture.options).isEmpty)
    }

    @Test func aFolderNamedWineWithoutAWinePrefixInsideIsLeftAlone() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.temp.makeFile("home/.wine/notes.txt", bytes: LeftoverScannerTests.BIG_BYTES)

        #expect(LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options).isEmpty)
    }

    @Test func aWinePrefixBehindALinkIsCleanedInsideAndTheLinkAndFolderStay() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let name = "mst-wine-\(UUID().uuidString)"
        let marker = UUID().uuidString
        let target = try fixture.temp.makeFolder("Volumes/SSD/\(name)")
        try Data(marker.utf8).write(to: URL(fileURLWithPath: target + "/system.reg"))
        try fixture.temp.makeFile("Volumes/SSD/\(name)/\(name).bin", bytes: LeftoverScannerTests.BIG_BYTES)
        try fixture.temp.makeLink("home/.wine", to: target)
        let trash = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        defer {
            try? FileManager.default.removeItem(atPath: trash + "/\(name).bin")
            // The marker file is named system.reg in the Trash too; remove only the one that holds this test's marker.
            for entry in PathTools.children(of: trash) where (try? String(contentsOfFile: entry, encoding: .utf8)) == marker {
                try? FileManager.default.removeItem(atPath: entry)
            }
        }
        let catalog = Catalog(entries: [])
        let report = try Scanner.scan(catalog: catalog, options: fixture.options)
        let item = try #require(report.items(in: .leftovers).first)
        #expect(item.linkTarget == target && item.size.bytes >= LeftoverScannerTests.BIG_BYTES)
        // The folder is on the external disk, so it does not count in the internal disk bar.
        #expect(report.internalBytes(in: .leftovers) == 0)
        #expect(report.items(in: .alreadyMoved).isEmpty)
        let optimizer = Optimizer(catalog: catalog, options: fixture.options, ownerCheck: { _ in nil })

        let result = optimizer.run(items: [item], mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.map(\.status) == [.done])
        #expect(PathTools.isSymlink(fixture.temp.sub("home/.wine")))
        #expect(PathTools.isDirectory(target) && PathTools.children(of: target).isEmpty)
        #expect(PathTools.exists(trash + "/\(name).bin"))
        // Nothing is left to list, so a new scan shows no leftover.
        #expect(try Scanner.scan(catalog: catalog, options: fixture.options).items(in: .leftovers).isEmpty)
    }

    @Test func aWineLinkToAnythingButAnExternalPrefixIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let elsewhere = try fixture.temp.makeFolder("home/Documents/important")
        try fixture.temp.makeFile("home/Documents/important/system.reg", bytes: LeftoverScannerTests.BIG_BYTES)
        try fixture.temp.makeLink("home/.wine", to: elsewhere)
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: fixture.options, ownerCheck: { _ in nil })
        let forged = ScanItem(
            path: fixture.temp.sub("home/.wine"), title: "~/.wine", catalogId: nil, category: .leftovers, action: .trashOnly, risk: .medium,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test", size: FolderSize(bytes: 1, isIncomplete: false), linkTarget: elsewhere
        )

        #expect(LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options).isEmpty)
        let result = optimizer.run(items: [forged], mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.map(\.status) == [.skipped("The Wine link does not point to a folder on a connected external disk.")])
        #expect(PathTools.exists(elsewhere))
    }

    @Test func aFolderThatTheCatalogNamesKeepsItsOwnAction() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.library("Application Support/com.isaacmarovitz.Whisky")
        let whisky = CatalogEntry(
            id: "whisky", path: "~/Library/Application Support/com.isaacmarovitz.Whisky", category: .apps, action: .move, risk: .medium,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test"
        )

        let report = try Scanner.scan(catalog: Catalog(entries: [whisky]), options: fixture.options)

        #expect(report.items(in: .leftovers).isEmpty)
        #expect(report.items(in: .apps).count == 1)
    }

    @Test func appsOnAnExternalDiskCountAsInstalledAndAMissingDiskStopsTheSearch() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let app = try fixture.temp.makeFolder("Volumes/SSD/Applications/Far.app/Contents")
        (["CFBundleIdentifier": "com.vendor.Far"] as NSDictionary).write(toFile: app + "/Info.plist", atomically: true)
        try fixture.library("Caches/com.vendor.Far")
        try fixture.library("Caches/com.vendor.Gone")

        let connected = LeftoverScanner.items(catalog: Catalog(entries: []), options: fixture.options)
        #expect(connected.map(\.title) == ["~/Library/Caches/com.vendor.Gone"])

        try fixture.temp.makeLink("home/.moved", to: fixture.temp.sub("Volumes/Unplugged/moved"))
        let report = try Scanner.scan(catalog: Catalog(entries: []), options: fixture.options)
        #expect(report.problems.contains { $0.kind == .diskNotMounted })
        #expect(report.items(in: .leftovers).isEmpty)
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
