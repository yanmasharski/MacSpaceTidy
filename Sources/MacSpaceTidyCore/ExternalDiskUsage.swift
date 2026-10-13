import Foundation

/// One external disk that holds moved folders.
public struct ExternalDiskUsage: Sendable, Identifiable {
    public let root: String
    public let space: DiskSpace
    /// Size of the folders moved there from this Mac.
    public let movedBytes: Int64

    public var id: String {
        return root
    }

    public var name: String {
        return (root as NSString).lastPathComponent
    }
}
