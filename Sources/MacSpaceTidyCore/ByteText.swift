import Foundation

public enum ByteText {
    /// Decimal units, like Finder.
    public static func format(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
