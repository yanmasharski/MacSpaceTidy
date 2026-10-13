import CoreServices
import Foundation

/// Lists old entries of the Downloads folder, one item each. These are your own files, not caches:
/// they are never checked by default and always go to the Trash. Moving to an external disk is the alternative.
public enum DownloadsScanner {
    public static let INSTALLER_AGE_DAYS = 30
    public static let OTHER_AGE_DAYS = 90
    private static let SECONDS_PER_DAY: TimeInterval = 86_400
    private static let INSTALLER_EXTENSIONS: Set<String> = ["dmg", "pkg", "mpkg", "iso", "exe", "msi"]
    private static let ARCHIVE_EXTENSIONS: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]
    private static let IGNORED_NAMES: Set<String> = [".DS_Store", ".localized", ".com.apple.containermanagerd.metadata.plist"]

    public enum Kind: Equatable {
        case installer
        case archive
        case other
    }

    public static func kind(ofName name: String) -> Kind {
        let ext = (name as NSString).pathExtension.lowercased()
        if INSTALLER_EXTENSIONS.contains(ext) {
            return .installer
        }
        return ARCHIVE_EXTENSIONS.contains(ext) ? .archive : .other
    }

    public static func ageThresholdDays(for kind: Kind) -> Int {
        return kind == .installer ? INSTALLER_AGE_DAYS : OTHER_AGE_DAYS
    }

    /// Old entries, biggest first. Links are skipped: they are reported as problems or moved folders.
    public static func items(options: ScanOptions, now: Date = Date(), progress: Scanner.Progress? = nil) -> [ScanItem] {
        var result: [ScanItem] = []
        for path in PathTools.children(of: options.downloadsPath) {
            let name = (path as NSString).lastPathComponent
            if IGNORED_NAMES.contains(name) || PathTools.isSymlink(path) {
                continue
            }
            progress?(PathTools.abbreviate(path, home: options.home))
            let size = FolderSize.measure(path: path)
            guard size.bytes >= options.minChildItemBytes else {
                continue
            }
            let kind = kind(ofName: name)
            let lastTouched = lastTouched(path: path, contentChange: size.newestChange)
            guard let days = days(since: lastTouched, now: now), days >= ageThresholdDays(for: kind) else {
                continue
            }
            result.append(ScanItem(
                path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .downloads,
                action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [],
                reason: reason(kind: kind, days: days), size: size, linkTarget: nil, canMove: true
            ))
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    public static func reason(kind: Kind, days: Int) -> String {
        switch kind {
        case .installer:
            return "Installer, not opened for \(days) days. The app is usually installed already. Goes to the Trash, or move it."
        case .archive:
            return "Archive, not opened for \(days) days. Check that you got what you needed from it."
        case .other:
            return "Your file, not opened for \(days) days. Goes to the Trash, or move it to the external disk."
        }
    }

    /// The latest of: the newest change inside, and the last time any app opened it (Spotlight).
    private static func lastTouched(path: String, contentChange: Date?) -> Date? {
        return [contentChange, lastOpened(path: path)].compactMap { $0 }.max()
    }

    private static func days(since date: Date?, now: Date) -> Int? {
        return date.map { Int(now.timeIntervalSince($0) / SECONDS_PER_DAY) }
    }

    private static func lastOpened(path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else {
            return nil
        }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
