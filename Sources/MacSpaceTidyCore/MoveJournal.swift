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
        try JsonLines.append(record, to: journalPath)
    }

    public static func read(from journalPath: String) -> [Record] {
        return JsonLines.read(Record.self, from: journalPath)
    }
}
