import Foundation

/// Fingerprint of a folder tree: counts, logical bytes, and an order-free hash of relative paths and sizes.
/// Two equal summaries mean the copy has the same files with the same sizes.
public struct TreeSummary: Sendable, Equatable {
    public let fileCount: Int
    public let folderCount: Int
    public let linkCount: Int
    public let logicalBytes: Int64
    /// Hash values are stable only inside one process run. Compare summaries made in the same run.
    public let pathHash: UInt64
    public let isComplete: Bool

    public static func make(path: String) -> TreeSummary {
        var fileCount = 0
        var folderCount = 0
        var linkCount = 0
        var logicalBytes: Int64 = 0
        var pathHash: UInt64 = 0
        var isComplete = true
        let rootLength = path.utf8.count
        guard let rootPath = strdup(path) else {
            return TreeSummary(fileCount: 0, folderCount: 0, linkCount: 0, logicalBytes: 0, pathHash: 0, isComplete: false)
        }
        defer { free(rootPath) }
        var rootPaths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        // FTS_COMFOLLOW: a root that is a link (a moved folder) is read through the link.
        guard let tree = fts_open(&rootPaths, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_NOCHDIR, nil) else {
            return TreeSummary(fileCount: 0, folderCount: 0, linkCount: 0, logicalBytes: 0, pathHash: 0, isComplete: false)
        }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            let kind = Int32(entry.pointee.fts_info)
            var size: Int64 = 0
            switch kind {
            case FTS_DP:
                continue
            case FTS_DNR, FTS_ERR, FTS_NS:
                isComplete = false
                continue
            case FTS_D:
                folderCount += 1
            case FTS_SL, FTS_SLNONE:
                linkCount += 1
            default:
                fileCount += 1
                size = Int64(entry.pointee.fts_statp?.pointee.st_size ?? 0)
                logicalBytes += size
            }
            let relativePath = String(decoding: String(cString: entry.pointee.fts_path).utf8.dropFirst(rootLength), as: UTF8.self)
            var hasher = Hasher()
            // HFS+ stores names decomposed (NFD), APFS keeps them as written. Compare one form.
            hasher.combine(relativePath.decomposedStringWithCanonicalMapping)
            hasher.combine(kind)
            hasher.combine(size)
            pathHash &+= UInt64(bitPattern: Int64(hasher.finalize()))
        }
        return TreeSummary(
            fileCount: fileCount, folderCount: folderCount, linkCount: linkCount,
            logicalBytes: logicalBytes, pathHash: pathHash, isComplete: isComplete
        )
    }
}
