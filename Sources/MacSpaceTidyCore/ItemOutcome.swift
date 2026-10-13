public struct ItemOutcome: Sendable {
    public enum Status: Sendable, Equatable {
        case done
        case skipped(String)
        case failed(String)
    }

    public let item: ScanItem
    public let status: Status
}
