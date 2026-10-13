import Foundation
import Testing
@testable import MacSpaceTidyCore

struct FolderSizeTests {
    private static let FILE_BYTES = 100_000

    @Test func countsFilesAndIgnoresLinkedFolders() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.makeFile("data/a.bin", bytes: FolderSizeTests.FILE_BYTES)
        try temp.makeFile("other/big.bin", bytes: FolderSizeTests.FILE_BYTES * 10)
        try temp.makeLink("data/link", to: temp.sub("other"))

        let size = FolderSize.measure(path: temp.sub("data"))

        #expect(size.bytes >= Int64(FolderSizeTests.FILE_BYTES))
        #expect(size.bytes < Int64(FolderSizeTests.FILE_BYTES * 2))
        #expect(!size.isIncomplete)
    }

    @Test func countsHardLinkedFileOnce() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let file = try temp.makeFile("data/a.bin", bytes: FolderSizeTests.FILE_BYTES)
        try FileManager.default.linkItem(atPath: file, toPath: temp.sub("data/b.bin"))

        let size = FolderSize.measure(path: temp.sub("data"))

        #expect(size.bytes < Int64(FolderSizeTests.FILE_BYTES * 2))
    }

    @Test func marksUnreadableFolderIncomplete() throws {
        let temp = try TempFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.sub("data/locked"))
            temp.remove()
        }
        try temp.makeFile("data/locked/a.bin", bytes: FolderSizeTests.FILE_BYTES)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: temp.sub("data/locked"))

        #expect(FolderSize.measure(path: temp.sub("data")).isIncomplete)
    }
}

struct TreeSummaryTests {
    @Test func sameNamesInDifferentUnicodeFormsMatch() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let composed = "\u{0439}.txt"
        let decomposed = "\u{0438}\u{0306}.txt"
        try temp.makeFile("a/\(composed)", bytes: 10)
        try temp.makeFile("b/\(decomposed)", bytes: 10)
        try temp.makeFile("c/other.txt", bytes: 10)

        #expect(TreeSummary.make(path: temp.sub("a")) == TreeSummary.make(path: temp.sub("b")))
        #expect(TreeSummary.make(path: temp.sub("a")) != TreeSummary.make(path: temp.sub("c")))
    }
}
