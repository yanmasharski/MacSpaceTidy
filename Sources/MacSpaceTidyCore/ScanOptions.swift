import Foundation

public struct ScanOptions: Sendable {
    public static let LINK_SEARCH_DEPTH = 3
    public static let LARGE_UNKNOWN_BYTES: Int64 = 1_000_000_000
    /// Single files of yours at least this big are listed in "Large files and folders".
    public static let LARGE_FILE_BYTES: Int64 = 500_000_000
    /// Identical files are searched among files of at least this size.
    public static let DUPLICATE_MIN_BYTES: Int64 = 50_000_000
    /// Children of a `/*` pattern smaller than this are hidden as noise.
    public static let MIN_CHILD_ITEM_BYTES: Int64 = 1_000_000
    public static let PROJECT_MIN_BYTES: Int64 = 10_000_000
    private static let DEFAULT_PROJECT_FOLDERS = ["Developer", "Projects", "Work", "Code", "dev", "src", "repos", "GitHub", "Documents/GitHub", "Documents/Projects"]

    public var home: String
    public var disks: ExternalDisks
    /// Folders whose big unknown children are listed as "Large, unknown".
    public var unknownParents: [String]
    public var linkRoots: [String]
    public var linkSearchDepth: Int
    public var largeUnknownBytes: Int64
    public var largeFileBytes: Int64
    public var duplicateMinBytes: Int64
    /// External disks the user chose to search for large files and duplicates too. Empty unless chosen.
    public var extraVolumes: [String]
    public var minChildItemBytes: Int64
    /// Run `simctl` and `tmutil`. Tests turn it off.
    public var usesSystemTools: Bool
    /// Measure folders that are already on an external disk. Slow: minutes for hundreds of GB.
    public var measuresMovedItems: Bool
    /// Folders searched for projects (build folders). More can be added in `project-roots.txt`.
    public var projectRoots: [String]
    /// Build folders smaller than this are noise.
    public var projectMinBytes: Int64
    /// Folders searched for installed apps. Their bundle ids tell which `~/Library` folders are leftovers.
    public var appFolders: [String]

    public init(home: String, disks: ExternalDisks, unknownParents: [String], linkRoots: [String], usesSystemTools: Bool) {
        self.home = home
        self.disks = disks
        self.unknownParents = unknownParents
        self.linkRoots = linkRoots
        self.linkSearchDepth = ScanOptions.LINK_SEARCH_DEPTH
        self.largeUnknownBytes = ScanOptions.LARGE_UNKNOWN_BYTES
        self.largeFileBytes = ScanOptions.LARGE_FILE_BYTES
        self.duplicateMinBytes = ScanOptions.DUPLICATE_MIN_BYTES
        self.extraVolumes = []
        self.minChildItemBytes = ScanOptions.MIN_CHILD_ITEM_BYTES
        self.usesSystemTools = usesSystemTools
        self.measuresMovedItems = false
        self.appFolders = []
        self.projectRoots = []
        self.projectMinBytes = ScanOptions.PROJECT_MIN_BYTES
    }

    /// The folder with your downloads. Its old entries are listed one by one, never as a whole.
    public var downloadsPath: String {
        return (home as NSString).appendingPathComponent("Downloads")
    }

    /// One JSON line per move. Lives on the internal disk; the catalog protects it.
    public var journalPath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/moves.jsonl")
    }

    /// Paths the user wants hidden and never cleaned. See `IgnoreList`.
    public var ignorePath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/ignore.txt")
    }

    /// Extra folders with your projects, one path per line. See `PathListFile`.
    public var projectRootsPath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/project-roots.txt")
    }

    /// One JSON line per cleaned item. See `CleanLog`.
    public var cleanLogPath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/cleanups.jsonl")
    }

    /// Sizes of folders on external disks from the last scan. Shown at once while a new count runs.
    public var sizeCachePath: String {
        return (home as NSString).appendingPathComponent("Library/Application Support/MacSpaceTidy/sizes.json")
    }

    public static func standard(home: String = NSHomeDirectory()) -> ScanOptions {
        let library = (home as NSString).appendingPathComponent("Library")
        var options = ScanOptions(
            home: home,
            disks: ExternalDisks(),
            unknownParents: [home, library, (library as NSString).appendingPathComponent("Application Support")],
            linkRoots: [home, "/Users/Shared", "/opt/homebrew"],
            usesSystemTools: true
        )
        options.projectRoots = DEFAULT_PROJECT_FOLDERS.map { (home as NSString).appendingPathComponent($0) }
        // Only disks the user chose, and only writable ones: a copy found there must be removable.
        let chosen = Set(SharedSettings.extraScanDisks)
        options.extraVolumes = options.disks.choices(internalPath: home).map(\.path).filter { chosen.contains($0) && access($0, W_OK) == 0 }
        options.appFolders = ["/Applications", "/System/Applications", (home as NSString).appendingPathComponent("Applications")]
        return options
    }
}
