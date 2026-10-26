import Foundation
import Testing
@testable import MacSpaceTidyCore

struct LargeFileScannerTests {
    private static let BIG_BYTES = 3_000_000

    private func options(for temp: TempFolder) throws -> ScanOptions {
        let home = try temp.makeFolder("home")
        var options = ScanOptions(
            home: home, disks: ExternalDisks(volumesRoot: temp.sub("Volumes")), unknownParents: [], linkRoots: [home], usesSystemTools: false
        )
        options.largeFileBytes = 2_000_000
        return options
    }

    @Test func listsBigFilesAndSkipsRepositoriesHiddenFilesAndSmallOnes() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        try temp.makeFile("home/Movies/film.mov", bytes: LargeFileScannerTests.BIG_BYTES)
        try temp.makeFile("home/Documents/small.bin", bytes: 100)
        try temp.makeFile("home/Documents/deep/er/archive.zip", bytes: LargeFileScannerTests.BIG_BYTES)
        try temp.makeFile("home/Documents/repo/data.bin", bytes: LargeFileScannerTests.BIG_BYTES)
        try temp.makeFolder("home/Documents/repo/.git")
        try temp.makeFile("home/Documents/.hidden.bin", bytes: LargeFileScannerTests.BIG_BYTES)
        try temp.makeFile("home/Library/Caches/big.bin", bytes: LargeFileScannerTests.BIG_BYTES)

        let items = LargeFileScanner.items(options: options)

        #expect(Set(items.map(\.title)) == ["~/Movies/film.mov", "~/Documents/deep/er/archive.zip"])
        #expect(items.allSatisfy { $0.action == .trashOnly && $0.canMove && !$0.checkedByDefault })
    }

    @Test func trashesOnlyListedKindsOfFiles() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        let big = try temp.makeFile("home/Movies/film.mov", bytes: LargeFileScannerTests.BIG_BYTES)
        let small = try temp.makeFile("home/Movies/clip.mov", bytes: 100)
        let inRepo = try temp.makeFile("home/Documents/repo/data.bin", bytes: LargeFileScannerTests.BIG_BYTES)
        try temp.makeFolder("home/Documents/repo/.git")
        let outside = try temp.makeFile("home/Library/big.bin", bytes: LargeFileScannerTests.BIG_BYTES)

        #expect(LargeFileScanner.canTrash(big, options: options))
        #expect(!LargeFileScanner.canTrash(small, options: options))
        #expect(!LargeFileScanner.canTrash(inRepo, options: options))
        #expect(!LargeFileScanner.canTrash(outside, options: options))
        #expect(!LargeFileScanner.canTrash(temp.sub("home/Movies"), options: options))
    }
}
