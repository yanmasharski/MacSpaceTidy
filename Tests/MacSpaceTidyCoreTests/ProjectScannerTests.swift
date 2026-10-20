import Foundation
import Testing
@testable import MacSpaceTidyCore

struct ProjectScannerTests {
    private static let BIG_BYTES = 2_000_000

    private struct Fixture {
        let temp: TempFolder
        let options: ScanOptions

        init() throws {
            temp = try TempFolder()
            let home = try temp.makeFolder("home")
            var options = ScanOptions(home: home, disks: ExternalDisks(volumesRoot: try temp.makeFolder("Volumes")), unknownParents: [home], linkRoots: [home], usesSystemTools: false)
            options.projectRoots = [temp.sub("home/Developer")]
            options.projectMinBytes = 1_000_000
            self.options = options
        }

        /// A project folder with a marker file and a big build folder.
        @discardableResult
        func project(_ name: String, marker: String, build: String) throws -> String {
            try temp.makeFile("home/Developer/\(name)/\(marker)", bytes: 10)
            return try temp.makeFile("home/Developer/\(name)/\(build)/blob", bytes: ProjectScannerTests.BIG_BYTES)
        }

        func git(_ project: String, _ arguments: String...) {
            let identity = ["-c", "user.name=test", "-c", "user.email=test@example.com"]
            _ = CommandRunner.run("/usr/bin/git", ["-C", temp.sub("home/Developer/\(project)")] + identity + arguments, timeoutSeconds: 30)
        }
    }

    @Test func listsBuildFoldersOnlyWhenTheProjectMarkerIsThere() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.project("web", marker: "package.json", build: "node_modules")
        try fixture.project("rust", marker: "Cargo.toml", build: "target")
        try fixture.project("swift", marker: "Package.swift", build: ".build")
        try fixture.project("game", marker: "ProjectSettings/ProjectVersion.txt", build: "Library")
        try fixture.project("android", marker: "build.gradle", build: "build")
        // No marker: a folder that only has the same name.
        try fixture.temp.makeFile("home/Developer/plain/node_modules/blob", bytes: ProjectScannerTests.BIG_BYTES)
        try fixture.temp.makeFile("home/Developer/plain/build/blob", bytes: ProjectScannerTests.BIG_BYTES)
        // Too small, and inside another build folder.
        try fixture.project("tiny", marker: "package.json", build: "dist").withTinyBlob()
        try fixture.temp.makeFile("home/Developer/web/node_modules/pkg/package.json", bytes: 10)
        try fixture.temp.makeFile("home/Developer/web/node_modules/pkg/node_modules/blob", bytes: ProjectScannerTests.BIG_BYTES)

        let items = ProjectScanner.items(options: fixture.options)

        #expect(Set(items.map(\.title)) == [
            "~/Developer/web/node_modules", "~/Developer/rust/target", "~/Developer/swift/.build",
            "~/Developer/game/Library", "~/Developer/android/build",
        ])
        #expect(items.allSatisfy { $0.category == .projects && $0.action == .trashOnly && !$0.checkedByDefault && !$0.canMove })
    }

    @Test func gitTrackedFilesKeysAndLinksKeepAFolderOutOfTheList() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        // A build folder that the project commits on purpose.
        try fixture.project("tracked", marker: "package.json", build: "dist")
        fixture.git("tracked", "init", "-q")
        fixture.git("tracked", "add", "-A")
        fixture.git("tracked", "commit", "-q", "-m", "x")
        // A repository that ignores its build folder: fine.
        try fixture.project("ignored", marker: "package.json", build: "node_modules")
        try "node_modules\n".write(toFile: fixture.temp.sub("home/Developer/ignored/.gitignore"), atomically: true, encoding: .utf8)
        fixture.git("ignored", "init", "-q")
        fixture.git("ignored", "add", "-A")
        fixture.git("ignored", "commit", "-q", "-m", "x")
        // A signing key next to the build output.
        try fixture.project("signed", marker: "package.json", build: "node_modules")
        try fixture.temp.makeFile("home/Developer/signed/node_modules/release.keystore", bytes: 10)
        // A link to a folder elsewhere.
        let elsewhere = try fixture.temp.makeFolder("home/Documents/elsewhere")
        try fixture.temp.makeFile("home/Documents/elsewhere/blob", bytes: ProjectScannerTests.BIG_BYTES)
        try fixture.temp.makeFile("home/Developer/linked/package.json", bytes: 10)
        try fixture.temp.makeLink("home/Developer/linked/node_modules", to: elsewhere)

        let titles = ProjectScanner.items(options: fixture.options).map(\.title)

        #expect(titles == ["~/Developer/ignored/node_modules"])
        #expect(ProjectScanner.refusal(fixture.temp.sub("home/Developer/tracked/dist"), options: fixture.options) == "Git tracks files inside it.")
        #expect(ProjectScanner.refusal(fixture.temp.sub("home/Developer/signed/node_modules"), options: fixture.options) == "It holds a signing key or a certificate.")
    }

    @Test func theOptimizerChecksAgainBeforeTheTrashAndRefusesForgedItems() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.project("web", marker: "package.json", build: "node_modules")
        try fixture.temp.makeFile("home/Documents/node_modules/blob", bytes: ProjectScannerTests.BIG_BYTES)
        let optimizer = Optimizer(catalog: Catalog(entries: []), options: fixture.options, ownerCheck: { _ in nil })
        let real = try #require(ProjectScanner.items(options: fixture.options).first)
        func forged(_ path: String, category: ItemCategory) -> ScanItem {
            return ScanItem(
                path: path, title: "x", catalogId: nil, category: category, action: .trashOnly, risk: .low, checkedByDefault: false,
                needsAdmin: false, ownerApps: [], reason: "test", size: FolderSize(bytes: 1, isIncomplete: false), linkTarget: nil
            )
        }

        #expect(optimizer.refusalReason(real) == nil)
        // Outside the project folders, or claiming another category to skip the project checks.
        #expect(optimizer.refusalReason(forged(fixture.temp.sub("home/Documents/node_modules"), category: .projects)) != nil)
        #expect(optimizer.refusalReason(forged(real.path, category: .caches)) != nil)
        // The marker disappears after the scan: it is not a known build folder any more.
        try FileManager.default.removeItem(atPath: fixture.temp.sub("home/Developer/web/package.json"))
        #expect(optimizer.refusalReason(real) == "Not a build folder of a project in your project folders.")
    }

    @Test func rootsKeepToTheHomeFolderAndReadTheListFile() throws {
        let fixture = try Fixture()
        defer { fixture.temp.remove() }
        try fixture.temp.makeFolder("home/Developer")
        try fixture.temp.makeFolder("home/Extra")
        try fixture.temp.makeFolder("Volumes/SSD/work")
        try fixture.temp.makeFolder("outside")
        try FileManager.default.createDirectory(atPath: (fixture.options.projectRootsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "# mine\n~/Extra\n\(fixture.temp.sub("Volumes/SSD/work"))\n\(fixture.temp.sub("outside"))\n/\n".write(toFile: fixture.options.projectRootsPath, atomically: true, encoding: .utf8)

        let roots = ProjectScanner.roots(options: fixture.options)

        #expect(roots == [fixture.temp.sub("home/Developer"), fixture.temp.sub("home/Extra")])
    }
}

private extension String {
    /// Shrinks the blob of a fixture build folder below the size limit.
    func withTinyBlob() throws {
        try Data(repeating: 1, count: 10).write(to: URL(fileURLWithPath: self))
    }
}
