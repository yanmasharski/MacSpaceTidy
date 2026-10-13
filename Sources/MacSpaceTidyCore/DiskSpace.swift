import Darwin

/// Volume numbers from `statfs`, the same source as `df`.
public struct DiskSpace: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64

    public var usedBytes: Int64 {
        return totalBytes - freeBytes
    }

    public init(totalBytes: Int64, freeBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }

    public static func read(path: String) -> DiskSpace? {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            return nil
        }
        let blockBytes = Int64(info.f_bsize)
        return DiskSpace(
            totalBytes: Int64(info.f_blocks) * blockBytes,
            freeBytes: Int64(info.f_bavail) * blockBytes
        )
    }
}
