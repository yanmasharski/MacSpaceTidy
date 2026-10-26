import Foundation
import Testing
@testable import MacSpaceTidyCore

struct DuplicateScannerTests {
    private static let BYTES = 3_000_000

    private func options(for temp: TempFolder) throws -> ScanOptions {
        let home = try temp.makeFolder("home")
        var options = ScanOptions(
            home: home, disks: ExternalDisks(volumesRoot: temp.sub("Volumes")), unknownParents: [], linkRoots: [home], usesSystemTools: false
        )
        options.duplicateMinBytes = 1_000_000
        return options
    }

    @Test func groupsIdenticalFilesAndIgnoresSameSizeWithOtherContentAndHardLinks() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        let first = try temp.makeFile("home/Movies/a.mov", bytes: DuplicateScannerTests.BYTES)
        try temp.makeFile("home/Documents/copy-of-a.mov", bytes: DuplicateScannerTests.BYTES)
        var other = Data(repeating: 7, count: DuplicateScannerTests.BYTES)
        other[DuplicateScannerTests.BYTES / 2] = 9
        try other.write(to: URL(fileURLWithPath: temp.sub("home/Documents/same-size-other.bin")))
        try FileManager.default.linkItem(atPath: first, toPath: temp.sub("home/Documents/hard-link.mov"))
        try temp.makeFile("home/Documents/repo/x.mov", bytes: DuplicateScannerTests.BYTES)
        try temp.makeFolder("home/Documents/repo/.git")

        let items = DuplicateScanner.items(options: options)

        #expect(items.count == 1)
        #expect(items[0].duplicateCopies.count == 2)
        // A hard link is the same file, so only one of its two names is listed.
        let paths = Set(items[0].duplicateCopies.map(\.path))
        #expect(paths.contains(temp.sub("home/Documents/copy-of-a.mov")))
        #expect(paths.contains(first) != paths.contains(temp.sub("home/Documents/hard-link.mov")))
        #expect(items[0].size.bytes == Int64(DuplicateScannerTests.BYTES))
    }

    @Test func trashesOnlyTheCopiesThatAreNotKeptAndChecksTheKeeperFirst() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        let id = UUID().uuidString
        let one = try temp.makeFile("home/Movies/mst-\(id).mov", bytes: DuplicateScannerTests.BYTES)
        let two = try temp.makeFile("home/Documents/mst-\(id)-2.mov", bytes: DuplicateScannerTests.BYTES)
        let three = try temp.makeFile("home/Desktop/mst-\(id)-3.mov", bytes: DuplicateScannerTests.BYTES)
        defer {
            for name in ["mst-\(id).mov", "mst-\(id)-2.mov", "mst-\(id)-3.mov"] {
                try? FileManager.default.removeItem(atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash/\(name)"))
            }
        }
        let group = try #require(DuplicateScanner.items(options: options).first)
        var plan = PlanSelection()
        plan.toggle(group)
        let keeperIndex = try #require(group.duplicateCopies.firstIndex { $0.path == two })
        plan.setKeeper(of: group, to: keeperIndex)
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: options, ownerCheck: { _ in nil })

        let removals = plan.chosenItems(from: [group])
        let result = optimizer.run(items: removals, mode: .deleteNow, isCancelled: { false })

        #expect(Set(removals.map(\.path)) == [one, three])
        #expect(result.outcomes.allSatisfy { $0.status == .done })
        #expect(PathTools.exists(two))
        #expect(!PathTools.exists(one) && !PathTools.exists(three))
    }

    @Test func refusesWhenTheKeptCopyChangedOrIsGone() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        try temp.makeFile("home/Movies/a.mov", bytes: DuplicateScannerTests.BYTES)
        try temp.makeFile("home/Documents/b.mov", bytes: DuplicateScannerTests.BYTES)
        let group = try #require(DuplicateScanner.items(options: options).first)
        var plan = PlanSelection()
        plan.toggle(group)
        let removal = try #require(plan.removals(of: group).first)
        let keeper = try #require(removal.keeperPath)
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: options, ownerCheck: { _ in nil })

        try Data(repeating: 1, count: DuplicateScannerTests.BYTES).write(to: URL(fileURLWithPath: keeper))
        #expect(optimizer.refusalReason(removal) == "The copies are not identical now. Scan again.")

        try FileManager.default.removeItem(atPath: keeper)
        #expect(optimizer.refusalReason(removal) == "A copy is gone or is not a plain file. Scan again.")
        #expect(PathTools.exists(removal.path))
    }

    @Test func checkedGroupWithoutAChoiceKeepsTheSuggestedCopyAndUncheckedKeepsAll() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let options = try options(for: temp)
        try temp.makeFile("home/Movies/a.mov", bytes: DuplicateScannerTests.BYTES)
        try temp.makeFile("home/Documents/b.mov", bytes: DuplicateScannerTests.BYTES)
        let group = try #require(DuplicateScanner.items(options: options).first)
        var plan = PlanSelection.defaults(for: [group])

        #expect(plan.chosenItems(from: [group]).isEmpty)

        plan.toggle(group)
        #expect(plan.chosenItems(from: [group]).map(\.path) == [group.duplicateCopies[1].path])
    }

    @Test func searchesAnExternalDiskOnlyWhenTheUserChoseIt() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        var options = try options(for: temp)
        try temp.makeFile("home/Movies/a.mov", bytes: DuplicateScannerTests.BYTES)
        let outside = try temp.makeFile("Volumes/Backup/a-copy.mov", bytes: DuplicateScannerTests.BYTES)
        try temp.makeFile("Volumes/Backup/\(Mover.FOLDER_NAME)/a-moved.mov", bytes: DuplicateScannerTests.BYTES)

        #expect(DuplicateScanner.items(options: options).isEmpty)

        options.extraVolumes = [temp.sub("Volumes/Backup")]
        let items = DuplicateScanner.items(options: options)

        #expect(items.count == 1)
        #expect(items[0].duplicateCopies.count == 2)
        #expect(items[0].duplicateCopies.contains { $0.path == outside && $0.diskName == "Backup" })
    }
}
