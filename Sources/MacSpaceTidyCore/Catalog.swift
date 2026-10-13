import Foundation

public struct Catalog: Sendable {
    private struct File: Codable {
        let entries: [CatalogEntry]
    }

    private static let BUNDLED_NAME = "catalog"
    private static let BUNDLED_EXTENSION = "json"

    public let entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
    }

    public init(data: Data) throws {
        self.entries = try JSONDecoder().decode(File.self, from: data).entries
    }

    /// True when deleting or moving `path` would touch a never-touch path, the home folder, or `/`.
    public func isProtected(_ path: String, home: String) -> Bool {
        if path == "/" || PathTools.isSameOrInside(home, folder: path) {
            return true
        }
        return entries.contains { entry in
            entry.action == .never && PathTools.overlaps(PathTools.expand(entry.path, home: home), path)
        }
    }

    /// The `.app` keeps the catalog in its Resources folder; `swift run` uses the package bundle.
    public static func loadBundled() throws -> Catalog {
        if let url = Bundle.main.url(forResource: BUNDLED_NAME, withExtension: BUNDLED_EXTENSION) {
            return try Catalog(data: Data(contentsOf: url))
        }
        guard let url = Bundle.module.url(forResource: BUNDLED_NAME, withExtension: BUNDLED_EXTENSION) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Catalog(data: Data(contentsOf: url))
    }
}
