import Foundation

/// One JSON object per line, appended to a file. Used by the move journal and the clean log.
enum JsonLines {
    static func append<Record: Encodable>(_ record: Record, to path: String) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(contentsOf: "\n".utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    static func read<Record: Decodable>(_ type: Record.Type, from path: String) -> [Record] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
    }
}
