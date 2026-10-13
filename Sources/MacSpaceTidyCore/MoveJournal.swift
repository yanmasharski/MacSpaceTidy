import Foundation

/// Appends one JSON line per finished move, so the user can see later what went where.
public enum MoveJournal {
    public struct Record: Codable, Sendable, Equatable {
        public let date: Date
        public let kind: String
        public let source: String
        public let destination: String
    }

    public static let KIND_MOVE = "move"
    public static let KIND_MOVE_BACK = "moveBack"

    public static func append(_ record: Record, to journalPath: String) throws {
        let folder = (journalPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(contentsOf: "\n".utf8)
        if !FileManager.default.fileExists(atPath: journalPath) {
            FileManager.default.createFile(atPath: journalPath, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: journalPath))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public static func read(from journalPath: String) -> [Record] {
        guard let text = try? String(contentsOfFile: journalPath, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
    }
}
