import Foundation

/// Remembers sizes measured on external disks, so the next scan can show them at once.
/// A cached size is a hint from an earlier scan; the UI must mark it until a new count replaces it.
public struct SizeCache: Sendable {
    private struct Entry: Codable {
        let bytes: Int64
        let isIncomplete: Bool
        let newestChange: Date?
        let measuredAt: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public static func load(from path: String) -> SizeCache {
        var cache = SizeCache()
        guard let data = FileManager.default.contents(atPath: path) else {
            return cache
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A damaged file is the same as no cache: the next scan measures again.
        cache.entries = (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
        return cache
    }

    public func size(for path: String) -> FolderSize? {
        return entries[path].map {
            FolderSize(bytes: $0.bytes, isIncomplete: $0.isIncomplete, newestChange: $0.newestChange, cachedAt: $0.measuredAt)
        }
    }

    public mutating func store(_ size: FolderSize, for path: String, at date: Date = Date()) {
        entries[path] = Entry(bytes: size.bytes, isIncomplete: size.isIncomplete, newestChange: size.newestChange, measuredAt: date)
    }

    /// Writes the cache, dropping paths that no longer exist.
    public func save(to path: String) throws {
        let alive = entries.filter { PathTools.exists($0.key) }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(alive).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
