import Foundation
import Testing
@testable import MacSpaceTidyCore

struct CatalogTests {
    @Test func bundledCatalogIsValid() throws {
        let catalog = try Catalog.loadBundled()

        #expect(!catalog.entries.isEmpty)
        #expect(Set(catalog.entries.map(\.id)).count == catalog.entries.count)
        for entry in catalog.entries {
            #expect(entry.path.hasPrefix("/") || entry.path.hasPrefix("~/"), "\(entry.id) has a relative path")
            #expect(!(entry.action == .never && entry.checkedByDefault), "\(entry.id) is never-touch but checked")
            #expect(!(entry.action == .move && entry.checkedByDefault), "\(entry.id): moves must not be checked by default")
            #expect(!entry.checkedByDefault || entry.risk == .low, "\(entry.id): only low risk items are checked by default")
            #expect(!entry.canMove || entry.action == .delete, "\(entry.id): canMove is for delete items only")
            #expect(!entry.reason.isEmpty, "\(entry.id) has no reason")
        }
    }

    @Test func bigToolCachesOfferMove() throws {
        let catalog = try Catalog.loadBundled()
        let movable = Set(catalog.entries.filter(\.canMove).map(\.id))

        #expect(movable.isSuperset(of: ["uv-cache", "yarn-berry-cache", "coursier-cache", "ivy-cache", "android-build-cache", "xcode-doc-cache"]))
        #expect(!movable.contains("library-caches"))
    }

    @Test func childrenPatternSkipsChildWithOwnEntry() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.makeFolder("Library/Caches/AppA")
        try temp.makeFolder("Library/Caches/Homebrew")
        let catalog = Catalog(entries: [
            entry(id: "caches", path: "~/Library/Caches/*"),
            entry(id: "brew", path: "~/Library/Caches/Homebrew"),
        ])

        let paths = Scanner.expandedPaths(of: catalog.entries[0], catalog: catalog, home: temp.path)

        #expect(paths == [temp.sub("Library/Caches/AppA")])
    }
}

func entry(id: String, path: String, action: ItemAction = .delete, category: ItemCategory = .caches) -> CatalogEntry {
    return CatalogEntry(
        id: id, path: path, category: category, action: action, risk: .low,
        checkedByDefault: action == .delete, needsAdmin: false, ownerApps: [], reason: "test"
    )
}
