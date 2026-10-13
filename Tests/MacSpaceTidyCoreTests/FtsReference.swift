import Foundation
@testable import MacSpaceTidyCore

/// Slow reference for `FolderSize.measure`: the first version, built on `fts`. Tests compare the fast one with it.
enum FtsReference {
    private struct FileIdentity: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private static let BLOCK_BYTES: Int64 = 512

    static func measure(path: String) -> FolderSize {
        guard let rootPath = strdup(path) else {
            return FolderSize(bytes: 0, isIncomplete: true)
        }
        defer { free(rootPath) }
        var rootPaths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        guard let tree = fts_open(&rootPaths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return FolderSize(bytes: 0, isIncomplete: true)
        }
        defer { fts_close(tree) }

        var total: Int64 = 0
        var isIncomplete = false
        var seenHardLinks = Set<FileIdentity>()
        var newestSeconds = 0
        while let entry = fts_read(tree) {
            let kind = Int32(entry.pointee.fts_info)
            switch kind {
            case FTS_DP:
                continue
            case FTS_DNR, FTS_ERR, FTS_NS:
                isIncomplete = true
                continue
            default:
                break
            }
            guard let info = entry.pointee.fts_statp?.pointee else {
                continue
            }
            newestSeconds = max(newestSeconds, info.st_mtimespec.tv_sec)
            if kind != FTS_D && info.st_nlink > 1 {
                let identity = FileIdentity(device: info.st_dev, inode: info.st_ino)
                if !seenHardLinks.insert(identity).inserted {
                    continue
                }
            }
            total += Int64(info.st_blocks) * BLOCK_BYTES
        }
        let newestChange = newestSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(newestSeconds)) : nil
        return FolderSize(bytes: total, isIncomplete: isIncomplete, newestChange: newestChange)
    }
}
