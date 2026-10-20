import Foundation
import Testing
@testable import MacSpaceTidyCore

struct IgnoreAndLogTests {
    private static let BIG_BYTES = 2_000_000

    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions
        let catalog: Catalog

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: try temp.makeFolder("Volumes")), unknownParents: [], linkRoots: [home], usesSystemTools: false)
            catalog = Catalog(entries: [CatalogEntry(
                id: "caches", path: "~/Library/Caches/*", category: .caches, action: .delete, risk: .low,
                checkedByDefault: true, needsAdmin: false, ownerApps: [], reason: "test"
            )])
            try temp.makeFile("home/Library/Caches/Keep/blob", bytes: IgnoreAndLogTests.BIG_BYTES)
            try temp.makeFile("home/Library/Caches/Drop/blob", bytes: IgnoreAndLogTests.BIG_BYTES)
        }

        func optimizer() -> Optimizer {
            return Optimizer(catalog: catalog, options: options, ownerCheck: { _ in nil })
        }
    }

    @Test func ignoredPathsAreHiddenFromTheScanAndKeptByTheOptimizer() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let before = try Scanner.scan(catalog: fixture.catalog, options: fixture.options)
        let keep = try #require(before.items.first { $0.title == "~/Library/Caches/Keep" })

        try IgnoreList.add(keep.path, options: fixture.options)
        try IgnoreList.add(keep.path, options: fixture.options)

        let after = try Scanner.scan(catalog: fixture.catalog, options: fixture.options)
        #expect(after.items.map(\.title) == ["~/Library/Caches/Drop"])
        #expect(try String(contentsOfFile: fixture.options.ignorePath, encoding: .utf8) == "~/Library/Caches/Keep\n")
        // A stale item from an older scan is refused too.
        let result = fixture.optimizer().run(items: [keep], mode: .deleteNow, isCancelled: { false })
        #expect(result.outcomes.map(\.status) == [.skipped("It is in your ignore list.")])
        #expect(PathTools.exists(fixture.temp.sub("home/Library/Caches/Keep/blob")))
    }

    @Test func theIgnoreFileSkipsCommentsAndCoversWhatIsInsideAPath() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try FileManager.default.createDirectory(atPath: (fixture.options.ignorePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "# my notes\n\n~/Library/Caches/Keep\n".write(toFile: fixture.options.ignorePath, atomically: true, encoding: .utf8)

        let list = try #require(IgnoreList.read(options: fixture.options))

        #expect(list == [fixture.temp.sub("home/Library/Caches/Keep")])
        #expect(IgnoreList.isIgnored(fixture.temp.sub("home/Library/Caches/Keep/deeper/file"), in: list))
        #expect(!IgnoreList.isIgnored(fixture.temp.sub("home/Library/Caches/Keeper"), in: list))
        #expect(!IgnoreList.isIgnored(fixture.temp.sub("home/Library/Caches"), in: list))
    }

    @Test func anUnreadableIgnoreFileStopsTheCleanInsteadOfCleaningEverything() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        // A folder in place of the file: it exists, but it cannot be read as text.
        try FileManager.default.createDirectory(atPath: fixture.options.ignorePath, withIntermediateDirectories: true)
        let item = try #require(try Scanner.scan(catalog: fixture.catalog, options: fixture.options).items.first)

        let result = fixture.optimizer().run(items: [item], mode: .deleteNow, isCancelled: { false })

        #expect(IgnoreList.read(options: fixture.options) == nil)
        #expect(result.outcomes.map(\.status) == [.skipped("The ignore list could not be read.")])
        #expect(PathTools.exists(item.path + "/blob"))
    }

    @Test func finishedCleansAreWrittenToTheLogAndSkippedOnesAreNot() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let items = try Scanner.scan(catalog: fixture.catalog, options: fixture.options).items
        let drop = try #require(items.first { $0.title == "~/Library/Caches/Drop" })
        try IgnoreList.add(fixture.temp.sub("home/Library/Caches/Keep"), options: fixture.options)
        let keep = try #require(items.first { $0.title == "~/Library/Caches/Keep" })

        _ = fixture.optimizer().run(items: [drop, keep], mode: .deleteNow, isCancelled: { false })

        let records = CleanLog.read(from: fixture.options.cleanLogPath)
        #expect(records.map(\.path) == [drop.path])
        #expect(records.first?.action == "delete" && records.first?.result == "done" && records.first?.bytes == drop.size.bytes)
    }
}
