import Foundation
import Testing
@testable import MacSpaceTidyCore

struct ExternalScannerTests {
    private static let BIG_BYTES = 2_000_000

    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions
        let catalog = Catalog(entries: [
            entry(id: "uv", path: "~/.cache-uv", category: .developer),
            entry(id: "gradle", path: "~/.gradle/caches", category: .developer),
        ])

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            let volumes = try temp.makeFolder("Volumes")
            options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: volumes), unknownParents: [], linkRoots: [home], usesSystemTools: false)
            try temp.makeFile("Volumes/SSD/uv/blob", bytes: ExternalScannerTests.BIG_BYTES)
            try temp.makeLink("home/.cache-uv", to: temp.sub("Volumes/SSD/uv"))
            try temp.makeFile("Volumes/SSD/gradle/caches/blob", bytes: ExternalScannerTests.BIG_BYTES)
            try temp.makeFile("Volumes/SSD/gradle/wrapper/keep", bytes: 10)
            try temp.makeLink("home/.gradle", to: temp.sub("Volumes/SSD/gradle"))
            try temp.makeFile("Volumes/SSD/MacSpaceTidy/old-copy/blob", bytes: ExternalScannerTests.BIG_BYTES)
            try MoveJournal.append(
                MoveJournal.Record(date: Date(), kind: MoveJournal.KIND_MOVE_BACK, source: temp.sub("Volumes/SSD/MacSpaceTidy/old-copy"), destination: temp.sub("home/old")),
                to: options.journalPath
            )
        }

        func fullReport() throws -> ScanReport {
            let report = try Scanner.scan(catalog: catalog, options: options)
            return ExternalScanner.scan(report: report, catalog: catalog, options: options)
        }

        func optimizer() -> Optimizer {
            return Optimizer(catalog: catalog, options: options, ownerCheck: { _ in nil }, adminRunner: { _ in nil })
        }
    }

    @Test func findsCachesInsideMovedFoldersAndOrphanCopies() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }

        let report = try fixture.fullReport()
        let cleanups = report.items(in: .external).map(\.path).sorted()

        #expect(cleanups == [
            fixture.temp.sub("Volumes/SSD/MacSpaceTidy/old-copy"),
            fixture.temp.sub("Volumes/SSD/gradle/caches"),
            fixture.temp.sub("home/.cache-uv"),
        ].sorted())
        #expect(report.items(in: .alreadyMoved).allSatisfy { $0.size.bytes > 0 && $0.size.newestChange != nil })
        #expect(report.externalDisks.map(\.root) == [fixture.temp.sub("Volumes/SSD")])
    }

    @Test func cachedScanShowsOldSizesAndFreshScanReplacesThem() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let base = try Scanner.scan(catalog: fixture.catalog, options: fixture.options)

        let beforeAnyCache = ExternalScanner.scan(report: base, catalog: fixture.catalog, options: fixture.options, mode: .cachedOnly)
        #expect(beforeAnyCache.items(in: .external).isEmpty)
        #expect(beforeAnyCache.items(in: .alreadyMoved).allSatisfy { $0.size.bytes == 0 && $0.size.cachedAt == nil })

        let fresh = ExternalScanner.scan(report: base, catalog: fixture.catalog, options: fixture.options, mode: .fresh)
        #expect(fresh.items.allSatisfy { $0.size.cachedAt == nil })

        let cached = ExternalScanner.scan(report: base, catalog: fixture.catalog, options: fixture.options, mode: .cachedOnly)
        // The same path can be in two categories (a moved cache is also a clean-up item).
        func key(_ item: ScanItem) -> String { "\(item.category.rawValue)|\(item.path)" }
        let sizesByPath = Dictionary(uniqueKeysWithValues: fresh.items.map { (key($0), $0.size.bytes) })
        #expect(cached.items(in: .alreadyMoved).allSatisfy { $0.size.cachedAt != nil })
        #expect(cached.items(in: .external).count == fresh.items(in: .external).count)
        #expect(cached.items.allSatisfy { $0.size.bytes == sizesByPath[key($0)] })
    }

    @Test func sizeCacheSurvivesRestartAndIgnoresDamagedFile() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let folder = try temp.makeFolder("data")
        let cachePath = temp.sub("cache/sizes.json")
        var cache = SizeCache()
        cache.store(FolderSize(bytes: 42, isIncomplete: false), for: folder)
        cache.store(FolderSize(bytes: 7, isIncomplete: false), for: temp.sub("gone"))

        try cache.save(to: cachePath)
        let loaded = SizeCache.load(from: cachePath)

        #expect(loaded.size(for: folder)?.bytes == 42)
        #expect(loaded.size(for: folder)?.cachedAt != nil)
        #expect(loaded.size(for: temp.sub("gone")) == nil)
        try Data("not json".utf8).write(to: URL(fileURLWithPath: cachePath))
        #expect(SizeCache.load(from: cachePath).size(for: folder) == nil)
    }

    @Test func cleaningEmptiesMovedCacheButKeepsLinkAndDeletesOrphan() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let report = try fixture.fullReport()

        let result = fixture.optimizer().run(items: report.items(in: .external), mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.allSatisfy { $0.status == .done })
        #expect(PathTools.linkTarget(fixture.temp.sub("home/.cache-uv")) == fixture.temp.sub("Volumes/SSD/uv"))
        #expect(PathTools.children(of: fixture.temp.sub("Volumes/SSD/uv")).isEmpty)
        #expect(FolderCleaner.isClean(fixture.temp.sub("Volumes/SSD/gradle/caches")))
        #expect(PathTools.isDirectory(fixture.temp.sub("Volumes/SSD/gradle/caches")))
        #expect(PathTools.exists(fixture.temp.sub("Volumes/SSD/gradle/wrapper/keep")))
        #expect(!PathTools.exists(fixture.temp.sub("Volumes/SSD/MacSpaceTidy/old-copy")))
    }

    @Test func deletesWholeCopyOnlyInsideToolFolder() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let outside = try fixture.temp.makeFolder("Volumes/SSD/user-data")
        let item = ScanItem(
            path: outside, title: "user-data", catalogId: nil, category: .external, action: .deleteExternalCopy, risk: .medium,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize(bytes: 0, isIncomplete: false), linkTarget: nil
        )

        #expect(fixture.optimizer().cleanExternalRefusal(item)?.hasPrefix("Only copies inside") == true)
    }

    @Test func refusesToCleanInternalFolders() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let internalFolder = try fixture.temp.makeFolder("home/Documents")
        let item = ScanItem(
            path: internalFolder, title: "Documents", catalogId: nil, category: .external, action: .cleanExternal, risk: .low,
            checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize(bytes: 0, isIncomplete: false), linkTarget: nil
        )

        #expect(fixture.optimizer().cleanExternalRefusal(item) == "It is not on a connected external disk.")
    }

    @Test func catalogMoveFlagDefaultsToFalse() throws {
        let json = #"{"entries": [{"id": "a", "path": "~/a", "category": "caches", "action": "delete", "risk": "low", "checkedByDefault": true, "needsAdmin": false, "ownerApps": [], "reason": "r"}]}"#
        let catalog = try Catalog(data: Data(json.utf8))

        #expect(catalog.entries.first?.canMove == false)
        #expect(try Catalog.loadBundled().entries.first { $0.id == "uv-cache" }?.canMove == true)
    }
}
