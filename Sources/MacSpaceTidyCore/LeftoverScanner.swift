import AppKit
import Foundation

/// Finds data that removed apps left in `~/Library`. A folder counts as a leftover when its name is a bundle id
/// (`com.vendor.App`) and no installed app has that id. Items are never checked by default and always go to the Trash.
public enum LeftoverScanner {
    private static let LIBRARY_FOLDERS = ["Application Support", "Caches", "Containers", "Group Containers", "WebKit", "Logs"]
    private static let APP_SEARCH_DEPTH = 3
    private static let GROUP_PREFIX = "group."
    private static let APPLE_PREFIX = "com.apple."
    /// Things that still run or start on their own: their ids are not leftovers.
    private static let SYSTEM_ID_FOLDERS = ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"]
    private static let REVERSE_DNS = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+){2,}$")
    private static let TEAM_PREFIX = try! NSRegularExpression(pattern: "^[A-Z0-9]{10}\\.")

    /// The folders whose direct entries may be listed as leftovers (and so trashed).
    public static func folders(options: ScanOptions) -> [String] {
        let library = (options.home as NSString).appendingPathComponent("Library")
        return LIBRARY_FOLDERS.map { (library as NSString).appendingPathComponent($0) }
    }

    public static func items(catalog: Catalog, options: ScanOptions, progress: Scanner.Progress? = nil) -> [ScanItem] {
        let installed = installedIds(options: options)
        // A path the catalog names itself (like the Whisky folder) keeps its own action.
        let ownPaths = Set(catalog.entries.filter { !$0.isChildrenPattern }.map { PathTools.expand($0.path, home: options.home) })
        var result: [ScanItem] = []
        for folder in folders(options: options) {
            for path in PathTools.children(of: folder) {
                let name = (path as NSString).lastPathComponent
                guard let id = appId(ofName: name), !ownPaths.contains(path), !PathTools.isSymlink(path), !catalog.isProtected(path, home: options.home),
                      !isInstalled(id, among: installed, options: options) else {
                    continue
                }
                progress?(PathTools.abbreviate(path, home: options.home))
                let size = FolderSize.measure(path: path)
                guard size.bytes >= options.minChildItemBytes else {
                    continue
                }
                result.append(ScanItem(
                    path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .leftovers,
                    action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [],
                    reason: reason(id: id), size: size, linkTarget: nil
                ))
            }
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    public static func reason(id: String) -> String {
        return "Data of \(id). No installed app has this id. It may hold that app's files. Goes to the Trash, so you can restore it."
    }

    /// The bundle id a folder name stands for, or nil when it is not one (or belongs to macOS).
    /// Group containers add `group.` or a team id in front: `group.com.vendor.App`, `ABCDE12345.com.vendor.App`.
    static func appId(ofName name: String) -> String? {
        var id = name
        if id.hasPrefix(GROUP_PREFIX) {
            id.removeFirst(GROUP_PREFIX.count)
        } else if let team = TEAM_PREFIX.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
            id.removeSubrange(Range(team.range, in: id)!)
        }
        let isReverseDns = REVERSE_DNS.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
        return isReverseDns && !id.lowercased().hasPrefix(APPLE_PREFIX) ? id : nil
    }

    /// Helpers and extensions have longer ids (`com.vendor.App.helper`), and a vendor folder has a shorter one,
    /// so an id matches when one is the start of the other.
    static func isInstalled(_ id: String, among installed: Set<String>, options: ScanOptions) -> Bool {
        if installed.contains(where: { $0 == id || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) {
            return true
        }
        // Launch Services also knows apps on external disks and in places we do not search.
        return options.usesSystemTools && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func installedIds(options: ScanOptions) -> Set<String> {
        var ids = Set<String>()
        // Apps kept on an external disk (Applications there) count as installed while the disk is connected.
        let diskApps = PathTools.children(of: options.disks.volumesRoot).map { ($0 as NSString).appendingPathComponent("Applications") }
        for folder in options.appFolders + diskApps {
            collectAppIds(in: folder, depth: APP_SEARCH_DEPTH, into: &ids)
        }
        if options.usesSystemTools {
            ids.formUnion(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let launchFolders = SYSTEM_ID_FOLDERS + [(options.home as NSString).appendingPathComponent("Library/LaunchAgents")]
            for folder in launchFolders {
                ids.formUnion(PathTools.children(of: folder).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension })
            }
        }
        return ids
    }

    private static func collectAppIds(in folder: String, depth: Int, into ids: inout Set<String>) {
        for path in PathTools.children(of: folder) {
            if path.hasSuffix(".app") {
                let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Contents/Info.plist"))
                if let id = info?["CFBundleIdentifier"] as? String {
                    ids.insert(id)
                }
            } else if depth > 1 && PathTools.isDirectory(path) {
                collectAppIds(in: path, depth: depth - 1, into: &ids)
            }
        }
    }
}
