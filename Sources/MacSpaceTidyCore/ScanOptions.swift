import Foundation

public struct ScanOptions: Sendable {
    public static let LINK_SEARCH_DEPTH = 3
    public static let LARGE_UNKNOWN_BYTES: Int64 = 1_000_000_000
    /// Children of a `/*` pattern smaller than this are hidden as noise.
    public static let MIN_CHILD_ITEM_BYTES: Int64 = 1_000_000

    public var home: String
    public var disks: ExternalDisks
    /// Folders whose big unknown children are listed as "Large, unknown".
    public var unknownParents: [String]
    public var linkRoots: [String]
    public var linkSearchDepth: Int
    public var largeUnknownBytes: Int64
    public var minChildItemBytes: Int64
    /// Run `simctl` and `tmutil`. Tests turn it off.
    public var usesSystemTools: Bool
    /// Measure folders that are already on an external disk. Slow: minutes for hundreds of GB.
    public var measuresMovedItems: Bool

    public init(home: String, disks: ExternalDisks, unknownParents: [String], linkRoots: [String], usesSystemTools: Bool) {
        self.home = home
        self.disks = disks
        self.unknownParents = unknownParents
        self.linkRoots = linkRoots
        self.linkSearchDepth = ScanOptions.LINK_SEARCH_DEPTH
        self.largeUnknownBytes = ScanOptions.LARGE_UNKNOWN_BYTES
        self.minChildItemBytes = ScanOptions.MIN_CHILD_ITEM_BYTES
        self.usesSystemTools = usesSystemTools
        self.measuresMovedItems = false
    }

    /// One JSON line per move. Lives on the internal disk; the catalog protects it.
    public var journalPath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/moves.jsonl")
    }

    /// Sizes of folders on external disks from the last scan. Shown at once while a new count runs.
    public var sizeCachePath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/sizes.json")
    }

    public static func standard(home: String = NSHomeDirectory()) -> ScanOptions {
        let library = (home as NSString).appendingPathComponent("Library")
        return ScanOptions(
            home: home,
            disks: ExternalDisks(),
            unknownParents: [home, library, (library as NSString).appendingPathComponent("Application Support")],
            linkRoots: [home, "/Users/Shared", "/opt/homebrew"],
            usesSystemTools: true
        )
    }
}
