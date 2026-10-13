import Foundation
import Testing
@testable import MacSpaceTidyCore

struct MoverTests {
    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions
        let diskRoot: String
        let catalog = Catalog(entries: [
            entry(id: "prefs", path: "~/Library/Preferences", action: .never, category: .system),
        ])

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            let volumes = try temp.makeFolder("Volumes")
            diskRoot = try temp.makeFolder("Volumes/SSD")
            options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: volumes), unknownParents: [], linkRoots: [], usesSystemTools: false)
            try temp.makeFile("home/AppData/a.bin", bytes: 1000)
            try temp.makeFile("home/AppData/sub/b.bin", bytes: 2000)
            try temp.makeLink("home/AppData/sub/link", to: "b.bin")
        }

        var source: String {
            return temp.sub("home/AppData")
        }

        var destination: String {
            return Mover.destination(for: source, diskRoot: diskRoot)
        }

        func item(action: ItemAction = .move) -> ScanItem {
            return ScanItem(
                path: source, title: "~/AppData", catalogId: nil, category: .apps, action: action, risk: .low,
                checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: "test",
                size: FolderSize.measure(path: source), linkTarget: nil
            )
        }

        func mover(copier: @escaping Mover.Copier = Mover.ditto) -> Mover {
            return Mover(catalog: catalog, options: options, copier: copier)
        }
    }

    @Test func movesFolderAndLeavesWorkingLink() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let before = TreeSummary.make(path: fixture.source)

        let status = fixture.mover().move(fixture.item(), diskRoot: fixture.diskRoot)

        #expect(status == .done)
        #expect(PathTools.linkTarget(fixture.source) == fixture.destination)
        #expect(TreeSummary.make(path: fixture.source) == before)
        #expect(!PathTools.exists(fixture.source + Mover.OLD_SUFFIX))
        #expect(MoveJournal.read(from: fixture.options.journalPath).map(\.kind) == [MoveJournal.KIND_MOVE])
    }

    @Test func refusesWhenDestinationExistsOrPathIsProtected() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try FileManager.default.createDirectory(atPath: fixture.destination, withIntermediateDirectories: true)

        #expect(fixture.mover().moveRefusal(fixture.item(), diskRoot: fixture.diskRoot)?.hasPrefix("The destination already exists") == true)
        #expect(fixture.mover().moveRefusal(fixture.item(action: .delete), diskRoot: fixture.diskRoot) == "This item cannot be moved.")
        #expect(fixture.mover().moveRefusal(fixture.item(), diskRoot: fixture.temp.sub("Volumes/Missing")) == "The disk is not connected.")
        #expect(!ExternalDisks.isSupported(fileSystem: "exfat"))
        #expect(ExternalDisks.isSupported(fileSystem: "apfs"))
    }

    @Test func badCopyChangesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let before = TreeSummary.make(path: fixture.source)
        let partialCopier: Mover.Copier = { source, destination in
            try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: source + "/a.bin", toPath: destination + "/a.bin")
            return nil
        }

        let status = fixture.mover(copier: partialCopier).move(fixture.item(), diskRoot: fixture.diskRoot)

        #expect(status == .failed("The copy is not the same as the original. Nothing changed."))
        #expect(!PathTools.isSymlink(fixture.source))
        #expect(TreeSummary.make(path: fixture.source) == before)
        #expect(!PathTools.exists(fixture.destination))
    }

    @Test func changeDuringCopyChangesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let writingCopier: Mover.Copier = { source, destination in
            let error = Mover.ditto(source, destination)
            try? Data([1]).write(to: URL(fileURLWithPath: source + "/new.bin"))
            return error
        }

        let status = fixture.mover(copier: writingCopier).move(fixture.item(), diskRoot: fixture.diskRoot)

        #expect(status == .failed("Files changed during the copy. Quit the app that uses the folder and try again."))
        #expect(!PathTools.isSymlink(fixture.source))
        #expect(!PathTools.exists(fixture.destination))
    }

    @Test func movesBackAndKeepsExternalCopy() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let before = TreeSummary.make(path: fixture.source)
        #expect(fixture.mover().move(fixture.item(), diskRoot: fixture.diskRoot) == .done)

        let status = fixture.mover().moveBack(fixture.item(action: .moveBack))

        #expect(status == .done)
        #expect(!PathTools.isSymlink(fixture.source))
        #expect(TreeSummary.make(path: fixture.source) == before)
        #expect(TreeSummary.make(path: fixture.destination) == before)
        #expect(MoveJournal.read(from: fixture.options.journalPath).map(\.kind) == [MoveJournal.KIND_MOVE, MoveJournal.KIND_MOVE_BACK])
    }
}
