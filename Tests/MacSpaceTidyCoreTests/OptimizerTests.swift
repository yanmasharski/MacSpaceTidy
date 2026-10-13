import Foundation
import Testing
@testable import MacSpaceTidyCore

struct OptimizerTests {
    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions
        let catalog = Catalog(entries: [
            entry(id: "caches", path: "~/Library/Caches/*"),
            entry(id: "prefs", path: "~/Library/Preferences", action: .never, category: .system),
        ])

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            options = ScanOptions(
                home: home,
                disks: ExternalDisks(volumesRoot: try temp.makeFolder("Volumes")),
                unknownParents: [],
                linkRoots: [],
                usesSystemTools: false
            )
        }

        func item(_ relative: String, action: ItemAction = .delete, needsAdmin: Bool = false) -> ScanItem {
            let path = temp.sub(relative)
            return ScanItem(
                path: path, title: relative, catalogId: nil, category: .caches, action: action, risk: .low,
                checkedByDefault: true, needsAdmin: needsAdmin, ownerApps: [], reason: "test",
                size: FolderSize(bytes: 0, isIncomplete: false), linkTarget: nil
            )
        }

        func optimizer(runningApp: String? = nil, adminRunner: @escaping Optimizer.AdminRunner = { _ in "no admin in tests" }) -> Optimizer {
            return Optimizer(catalog: catalog, options: options, ownerCheck: { _ in runningApp }, adminRunner: adminRunner)
        }
    }

    @Test func deletesNowAndRefusesUnsafeItems() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        let temp = fixture.temp
        try temp.makeFile("home/Library/Caches/AppA/blob", bytes: 10)
        try temp.makeFile("home/Library/Preferences/app.plist", bytes: 10)
        try temp.makeFile("Volumes/SSD/AppB/blob", bytes: 10)
        try temp.makeLink("home/Library/Caches/AppB", to: temp.sub("Volumes/SSD/AppB"))
        try temp.makeFile("home/Library/Caches/AppC/blob", bytes: 10)

        let items = [
            fixture.item("home/Library/Caches/AppA"),
            fixture.item("home/Library/Preferences"),
            fixture.item("home/Library/Caches/AppB"),
            fixture.item("home/Library/Caches/AppC", action: .move),
            fixture.item("home"),
        ]
        let result = fixture.optimizer().run(items: items, mode: .deleteNow, isCancelled: { false })
        let statuses = result.outcomes.map(\.status)

        #expect(statuses[0] == .done)
        #expect(statuses[1] == .skipped("Protected path."))
        #expect(statuses[2] == .skipped("It is a link now. Scan again."))
        #expect(statuses[3] == .skipped("Choose an external disk first."))
        #expect(statuses[4] == .skipped("Protected path."))
        #expect(FolderCleaner.isClean(temp.sub("home/Library/Caches/AppA")))
        #expect(PathTools.isDirectory(temp.sub("home/Library/Caches/AppA")))
        #expect(PathTools.exists(temp.sub("home/Library/Preferences/app.plist")))
        #expect(PathTools.exists(temp.sub("Volumes/SSD/AppB/blob")))
    }

    @Test func skipsItemWhenOwnerAppRuns() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.temp.makeFile("home/Library/Caches/AppA/blob", bytes: 10)

        let result = fixture.optimizer(runningApp: "AppA").run(items: [fixture.item("home/Library/Caches/AppA")], mode: .deleteNow, isCancelled: { false })

        #expect(result.outcomes.first?.status == .skipped("AppA is running. Quit it first."))
        #expect(PathTools.exists(fixture.temp.sub("home/Library/Caches/AppA")))
    }

    @Test func stopsOnCancelAndBatchesAdminItems() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.temp.makeFile("home/Library/Caches/AppA/blob", bytes: 10)
        try fixture.temp.makeFile("system/Cache/blob", bytes: 10)
        let adminItem = fixture.item("system/Cache", needsAdmin: true)

        let cancelled = fixture.optimizer().run(items: [fixture.item("home/Library/Caches/AppA"), adminItem], mode: .deleteNow, isCancelled: { true })
        #expect(cancelled.wasCancelled)
        #expect(cancelled.outcomes.isEmpty)

        let commands = CommandLog()
        let result = fixture.optimizer(adminRunner: { list in
            commands.append(list)
            return "canceled"
        }).run(items: [adminItem], mode: .trash, isCancelled: { false })
        #expect(commands.all == [["/usr/bin/find '\(fixture.temp.sub("system/Cache"))' -mindepth 1 -delete"]])
        #expect(result.outcomes.first?.status == .failed("canceled"))
    }

    @Test func quotesShellPaths() {
        #expect(AdminShell.shellQuoted("/a b/it's") == "'/a b/it'\\''s'")
    }
}

private final class CommandLog: @unchecked Sendable {
    private(set) var all: [[String]] = []

    func append(_ commands: [String]) {
        all.append(commands)
    }
}
