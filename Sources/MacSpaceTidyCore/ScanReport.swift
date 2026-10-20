public struct ScanReport: Sendable {
    public let disk: DiskSpace
    public let items: [ScanItem]
    public let problems: [Problem]
    /// Filled by `ExternalScanner` after the main scan. Empty until then.
    public let externalDisks: [ExternalDiskUsage]

    public init(disk: DiskSpace, items: [ScanItem], problems: [Problem], externalDisks: [ExternalDiskUsage] = []) {
        self.disk = disk
        self.items = items
        self.problems = problems
        self.externalDisks = externalDisks
    }

    public func items(in category: ItemCategory) -> [ScanItem] {
        return items.filter { $0.category == category }
    }

    public func totalBytes(in category: ItemCategory) -> Int64 {
        return items(in: category).reduce(0) { $0 + $1.size.bytes }
    }

    /// Bytes that really sit on the internal disk. An item behind a link to an external disk is not counted.
    public func internalBytes(in category: ItemCategory) -> Int64 {
        return items(in: category).filter { $0.linkTarget == nil }.reduce(0) { $0 + $1.size.bytes }
    }

    /// True when some folders could not be read. The UI then asks for Full Disk Access.
    public var hasUnreadableFolders: Bool {
        return items.contains { $0.size.isIncomplete }
    }
}
