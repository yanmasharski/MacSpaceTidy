/// A symbolic link found during the scan.
public struct LinkInfo: Sendable, Equatable {
    public let path: String
    public let target: String
}
