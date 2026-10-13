/// An external disk the user can move folders to.
public struct DiskChoice: Sendable, Identifiable, Equatable {
    public let path: String
    public let name: String
    public let fileSystem: String
    public let freeBytes: Int64
    /// Nil when folders can be moved there, else the reason why not.
    public let problem: String?

    public var id: String {
        return path
    }
}
