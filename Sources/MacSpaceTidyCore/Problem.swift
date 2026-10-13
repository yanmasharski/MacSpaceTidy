public struct Problem: Sendable, Equatable {
    public let kind: ProblemKind
    /// The link or folder with the problem. Nil for disk-wide problems.
    public let path: String?
    public let detail: String

    public init(kind: ProblemKind, path: String?, detail: String) {
        self.kind = kind
        self.path = path
        self.detail = detail
    }
}
