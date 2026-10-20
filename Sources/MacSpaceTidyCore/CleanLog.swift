import Foundation

/// One JSON line per cleaned item (Trash or delete), so the user can see later what was removed and when.
/// Moves have their own journal (`MoveJournal`).
public enum CleanLog {
    public struct Record: Codable, Sendable, Equatable {
        public let date: Date
        /// `trash` or `delete`.
        public let action: String
        public let path: String
        public let bytes: Int64
        /// `done`, or `failed: <reason>`.
        public let result: String

        public init(date: Date, action: String, path: String, bytes: Int64, result: String) {
            self.date = date
            self.action = action
            self.path = path
            self.bytes = bytes
            self.result = result
        }
    }

    public static func append(_ record: Record, to logPath: String) throws {
        try JsonLines.append(record, to: logPath)
    }

    public static func read(from logPath: String) -> [Record] {
        return JsonLines.read(Record.self, from: logPath)
    }
}
