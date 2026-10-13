import Foundation
import Testing
@testable import MacSpaceTidyCore

struct ScannerTests {
    private static let BIG_BYTES = 2_000_000

    @Test func classifiesCatalogMovedUnknownAndSkipsInsideMovedFolders() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let home = try temp.makeFolder("home")
        let volumes = try temp.makeFolder("Volumes")
        try temp.makeFile("home/Library/Caches/AppA/blob", bytes: ScannerTests.BIG_BYTES)
        try temp.makeFile("home/Library/Caches/Tiny/blob", bytes: 10)
        try temp.makeFile("Volumes/SSD/uv/blob", bytes: ScannerTests.BIG_BYTES)
        try temp.makeLink("home/.cache-uv", to: temp.sub("Volumes/SSD/uv"))
        try temp.makeFile("Volumes/SSD/gradle/caches/blob", bytes: ScannerTests.BIG_BYTES)
        try temp.makeLink("home/.gradle", to: temp.sub("Volumes/SSD/gradle"))
        try temp.makeFile("home/Movies/film.bin", bytes: ScannerTests.BIG_BYTES)
        try temp.makeFile("home/Library/Preferences/big.plist", bytes: ScannerTests.BIG_BYTES)

        let catalog = Catalog(entries: [
            entry(id: "caches", path: "~/Library/Caches/*"),
            entry(id: "uv", path: "~/.cache-uv", category: .developer),
            entry(id: "gradle", path: "~/.gradle/caches", category: .developer),
            entry(id: "prefs", path: "~/Library/Preferences", action: .never, category: .system),
        ])
        var options = ScanOptions(
            home: home,
            disks: ExternalDisks(volumesRoot: volumes),
            unknownParents: [home, temp.sub("home/Library")],
            linkRoots: [home],
            usesSystemTools: false
        )
        options.largeUnknownBytes = 1_000_000

        let report = try Scanner.scan(catalog: catalog, options: options)
        let categoriesByTitle = Dictionary(uniqueKeysWithValues: report.items.map { ($0.title, $0.category) })

        #expect(categoriesByTitle == [
            "~/Library/Caches/AppA": .caches,
            "~/.cache-uv": .alreadyMoved,
            "~/.gradle": .alreadyMoved,
            "~/Movies": .largeUnknown,
        ])
    }
}
