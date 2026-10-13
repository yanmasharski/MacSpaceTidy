/// An external disk the user can move folders to.
public struct DiskChoice: Sendable, Identifiable, Equatable {
    public let path: String
    public let name: String
    public let fileSystem: String
    public let freeBytes: Int64
    /// Nil when folders can be moved there, else the reason why not.
    public let problem: String?

    public init(path: String, name: String, fileSystem: String, freeBytes: Int64, problem: String?) {
        self.path = path
        self.name = name
        self.fileSystem = fileSystem
        self.freeBytes = freeBytes
        self.problem = problem
    }

    public var id: String {
        return path
    }
}
