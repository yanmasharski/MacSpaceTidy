import Foundation
import Testing
@testable import MacSpaceTidyCore

struct ProblemFinderTests {
    @Test func findsLinkProblemsAndIgnoresChromiumLocks() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let volumes = try temp.makeFolder("Volumes")
        try temp.makeFolder("Volumes/SSD/Caches")
        try temp.makeFolder("home/Library/Caches")
        try temp.makeLink("home/Library/Caches/Caches", to: temp.sub("Volumes/SSD/Caches"))
        try temp.makeLink("home/gone", to: temp.sub("nothing-here"))
        try temp.makeLink("home/SingletonLock", to: "myhost-12345")
        try temp.makeLink("home/offline", to: temp.sub("Volumes/Unplugged/data"))
        let links = LinkFinder.findLinks(roots: [temp.sub("home")], maxDepth: 3)

        let problems = ProblemFinder.linkProblems(links: links, disks: ExternalDisks(volumesRoot: volumes))
        let kindsByPath = Dictionary(uniqueKeysWithValues: problems.map { ($0.path ?? "", $0.kind) })

        #expect(kindsByPath == [
            temp.sub("home/Library/Caches/Caches"): .strayNestedLink,
            temp.sub("home/gone"): .brokenLink,
            temp.sub("home/offline"): .diskNotMounted,
        ])
    }

    @Test func reportsLowFreeSpace() {
        let gigabyte: Int64 = 1_000_000_000
        #expect(ProblemFinder.freeSpaceProblem(disk: DiskSpace(totalBytes: 500 * gigabyte, freeBytes: 15 * gigabyte)) != nil)
        #expect(ProblemFinder.freeSpaceProblem(disk: DiskSpace(totalBytes: 1000 * gigabyte, freeBytes: 90 * gigabyte)) != nil)
        #expect(ProblemFinder.freeSpaceProblem(disk: DiskSpace(totalBytes: 250 * gigabyte, freeBytes: 75 * gigabyte)) == nil)
    }

    @Test func parsesSimulatorRuntimes() throws {
        let json = """
        {"A": {"identifier": "A", "version": "18.5", "build": "22F77", "sizeBytes": 8837333817,
               "deletable": true, "platformIdentifier": "com.apple.platform.iphonesimulator"},
         "B": {"identifier": "B", "version": "1.0", "deletable": false}}
        """
        let runtimes = try #require(SystemTools.parseSimulatorRuntimes(json: Data(json.utf8)))

        #expect(runtimes == [SystemTools.SimulatorRuntime(identifier: "A", name: "iOS 18.5 (22F77)", sizeBytes: 8837333817)])
    }
}
