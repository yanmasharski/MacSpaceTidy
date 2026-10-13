public struct OptimizeResult: Sendable {
    public let outcomes: [ItemOutcome]
    public let diskBefore: DiskSpace
    public let diskAfter: DiskSpace
    public let wasCancelled: Bool

    /// Real gain from `df`, not the sum of item sizes.
    public var freedBytes: Int64 {
        return diskAfter.freeBytes - diskBefore.freeBytes
    }
}
