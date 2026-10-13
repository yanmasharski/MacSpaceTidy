import Foundation
@testable import MacSpaceTidyCore

/// A fresh folder under the system temp folder, removed by `remove()`.
struct TempFolder {
    let path: String

    init() throws {
        let base = PathTools.resolved(NSTemporaryDirectory())
        path = (base as NSString).appendingPathComponent("MacSpaceTidyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func sub(_ relative: String) -> String {
        return (path as NSString).appendingPathComponent(relative)
    }

    @discardableResult
    func makeFolder(_ relative: String) throws -> String {
        let folder = sub(relative)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    func makeFile(_ relative: String, bytes: Int) throws -> String {
        let file = sub(relative)
        try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: URL(fileURLWithPath: file))
        return file
    }

    func makeLink(_ relative: String, to target: String) throws {
        try FileManager.default.createSymbolicLink(atPath: sub(relative), withDestinationPath: target)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
