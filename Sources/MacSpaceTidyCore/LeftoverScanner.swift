import AppKit
import Foundation

/// Finds data that removed apps left behind. Items are never checked by default and always go to the Trash.
///
/// Three kinds, from the most to the least sure:
/// 1. A `~/Library` folder named by a bundle id (`com.vendor.App`) that no installed app has.
/// 2. A Wine prefix (`~/.wine`) when Wine is not installed. It may be a link to a folder on an external disk.
/// 3. A folder of `Application Support` that no installed app is named after. Risk is high: it may be a game or a tool.
public enum LeftoverScanner {
    private static let LIBRARY_FOLDERS = ["Application Support", "Caches", "Containers", "Group Containers", "WebKit", "Logs"]
    private static let APPLICATION_SUPPORT = "Application Support"
    private static let APP_SEARCH_DEPTH = 3
    private static let GROUP_PREFIX = "group."
    private static let APPLE_PREFIX = "com.apple."
    /// Name matches are less sure, so tiny folders are left out (also a folder that the user chose to skip).
    private static let NAME_MATCH_MIN_BYTES: Int64 = 20_000_000
    /// Things that still run or start on their own: their ids are not leftovers.
    private static let SYSTEM_ID_FOLDERS = ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"]
    /// macOS keeps its own data here (iPhone backups, contacts, the Dock). Never judged by name.
    private static let SYSTEM_FOLDER_NAMES: Set<String> = [
        "addressbook", "animoji", "callhistorydb", "callhistorytransactions", "caches", "clouddocs", "crashreporter",
        "differentialprivacy", "diskimages", "dock", "facetime", "fileprovider", "ilifemediabrowser", "knowledge",
        "mobilesync", "networkserviceproxy", "quick look", "syncservices",
    ]
    private static let WINE_PREFIX_NAME = ".wine"
    private static let WINE_MARKER_FILE = "system.reg"
    private static let WINE_NAME_PREFIX = "wine"
    private static let WINE_APP_NAMES: Set<String> = ["crossover"]
    private static let WINE_BINARIES = ["/opt/homebrew/bin/wine", "/opt/homebrew/bin/wine64", "/usr/local/bin/wine", "/usr/local/bin/wine64", "/opt/local/bin/wine"]
    private static let REVERSE_DNS = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+){2,}$")
    private static let TEAM_PREFIX = try! NSRegularExpression(pattern: "^[A-Z0-9]{10}\\.")

    struct Installed {
        var ids = Set<String>()
        /// Lowercase letters and digits only: app names, executable names, and the vendor and last parts of ids.
        var names = Set<String>()

        /// An exact match, or one name starting the other (`Epic` and `EpicGamesLauncher`). A wrong match only hides a leftover.
        func matches(name: String) -> Bool {
            return names.contains { $0 == name || ($0.count >= Installed.MIN_PREFIX && name.hasPrefix($0)) || (name.count >= Installed.MIN_PREFIX && $0.hasPrefix(name)) }
        }

        static let MIN_PREFIX = 4
    }

    /// The folders whose direct entries may be listed as leftovers (and so trashed).
    public static func folders(options: ScanOptions) -> [String] {
        let library = (options.home as NSString).appendingPathComponent("Library")
        return LIBRARY_FOLDERS.map { (library as NSString).appendingPathComponent($0) }
    }

    public static func winePrefix(options: ScanOptions) -> String {
        return (options.home as NSString).appendingPathComponent(WINE_PREFIX_NAME)
    }

    /// True for a direct entry of a leftover folder, and for the Wine prefix.
    public static func canTrash(_ path: String, options: ScanOptions) -> Bool {
        return path == winePrefix(options: options) || folders(options: options).contains((path as NSString).deletingLastPathComponent)
    }

    public static func items(catalog: Catalog, options: ScanOptions, progress: Scanner.Progress? = nil) -> [ScanItem] {
        let installed = installedApps(options: options)
        // A path the catalog names itself (like the Whisky folder) keeps its own action.
        let ownPaths = Set(catalog.entries.filter { !$0.isChildrenPattern }.map { PathTools.expand($0.path, home: options.home) })
        var result: [ScanItem] = []
        for folder in folders(options: options) {
            for path in PathTools.children(of: folder) {
                let name = (path as NSString).lastPathComponent
                guard !ownPaths.contains(path), !PathTools.isSymlink(path), !catalog.isProtected(path, home: options.home),
                      let verdict = verdict(name: name, inApplicationSupport: folder.hasSuffix(APPLICATION_SUPPORT), installed: installed, options: options) else {
                    continue
                }
                progress?(PathTools.abbreviate(path, home: options.home))
                let size = FolderSize.measure(path: path)
                guard size.bytes >= verdict.minBytes else {
                    continue
                }
                result.append(ScanItem(
                    path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .leftovers,
                    action: .trashOnly, risk: verdict.risk, checkedByDefault: false, needsAdmin: false, ownerApps: [],
                    reason: verdict.reason, size: size, linkTarget: nil
                ))
            }
        }
        if let wine = wineItem(installed: installed, ownPaths: ownPaths, options: options, progress: progress) {
            result.append(wine)
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    public static func reason(id: String) -> String {
        return "Data of \(id). No installed app has this id. It may hold that app's files. Goes to the Trash, so you can restore it."
    }

    public static func reason(unmatchedName name: String) -> String {
        return "No installed app is named \(name). It may be left by a removed app, or it may belong to a game or a tool. "
            + "Check it before you trash it. Goes to the Trash, so you can restore it."
    }

    private static func reason(winePrefixIsLinked isLinked: Bool) -> String {
        return "A Wine prefix: a Windows folder with its programs. Wine is not installed. "
            + (isLinked ? "Goes to the Trash together with its link." : "Goes to the Trash, so you can restore it.")
    }

    private struct Verdict {
        let reason: String
        let risk: Risk
        let minBytes: Int64
    }

    /// Nil when the folder is not a leftover.
    private static func verdict(name: String, inApplicationSupport: Bool, installed: Installed, options: ScanOptions) -> Verdict? {
        if let id = appId(ofName: name) {
            return isInstalled(id, among: installed.ids, options: options) ? nil
                : Verdict(reason: reason(id: id), risk: .medium, minBytes: options.minChildItemBytes)
        }
        // Names of macOS and of other id-shaped folders (com.apple.*) are never judged by name.
        guard inApplicationSupport, idShape(ofName: name) == nil, !SYSTEM_FOLDER_NAMES.contains(name.lowercased()),
              !installed.matches(name: normalized(name)) else {
            return nil
        }
        return Verdict(reason: reason(unmatchedName: name), risk: .high, minBytes: NAME_MATCH_MIN_BYTES)
    }

    // MARK: Wine

    private static func wineItem(installed: Installed, ownPaths: Set<String>, options: ScanOptions, progress: Scanner.Progress?) -> ScanItem? {
        let path = winePrefix(options: options)
        let target = PathTools.linkTarget(path)
        let folder = target ?? path
        guard !ownPaths.contains(path), PathTools.isDirectory(folder), PathTools.exists((folder as NSString).appendingPathComponent(WINE_MARKER_FILE)),
              target == nil || options.disks.isOnExternalDisk(folder), !isWineInstalled(installed, options: options) else {
            return nil
        }
        progress?(PathTools.abbreviate(path, home: options.home))
        let size = FolderSize.measure(path: folder)
        guard size.bytes >= options.minChildItemBytes else {
            return nil
        }
        return ScanItem(
            path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .leftovers,
            action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [],
            reason: reason(winePrefixIsLinked: target != nil), size: size, linkTarget: target
        )
    }

    private static func isWineInstalled(_ installed: Installed, options: ScanOptions) -> Bool {
        if installed.names.contains(where: { $0.hasPrefix(WINE_NAME_PREFIX) || WINE_APP_NAMES.contains($0) }) {
            return true
        }
        return options.usesSystemTools && WINE_BINARIES.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Nil when the Wine prefix link may be removed together with the folder it points to.
    public static func linkedPrefixRefusal(options: ScanOptions) -> String? {
        guard let target = PathTools.linkTarget(winePrefix(options: options)), options.disks.isOnExternalDisk(target),
              options.disks.isMounted(target), PathTools.isDirectory(target), !PathTools.isSymlink(target) else {
            return "The Wine link does not point to a folder on a connected external disk."
        }
        guard options.disks.volumeRoot(of: target) != target, PathTools.exists((target as NSString).appendingPathComponent(WINE_MARKER_FILE)) else {
            return "The folder behind the Wine link is not a Wine prefix."
        }
        return nil
    }

    // MARK: Names and ids

    /// The id inside a folder name, if the name is id-shaped. Group containers add `group.` or a team id in front:
    /// `group.com.vendor.App`, `ABCDE12345.com.vendor.App`.
    private static func idShape(ofName name: String) -> String? {
        var id = name
        if id.hasPrefix(GROUP_PREFIX) {
            id.removeFirst(GROUP_PREFIX.count)
        } else if let team = TEAM_PREFIX.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
            id.removeSubrange(Range(team.range, in: id)!)
        }
        return REVERSE_DNS.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil ? id : nil
    }

    /// The bundle id a folder name stands for, or nil when it is not one (or belongs to macOS).
    static func appId(ofName name: String) -> String? {
        guard let id = idShape(ofName: name), !id.lowercased().hasPrefix(APPLE_PREFIX) else {
            return nil
        }
        return id
    }

    private static func normalized(_ name: String) -> String {
        return String(name.lowercased().filter { $0.isLetter || $0.isNumber })
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

    static func installedApps(options: ScanOptions) -> Installed {
        var installed = Installed()
        // Apps kept on an external disk (Applications there) count as installed while the disk is connected.
        let diskApps = PathTools.children(of: options.disks.volumesRoot).map { ($0 as NSString).appendingPathComponent("Applications") }
        for folder in options.appFolders + diskApps {
            collectApps(in: folder, depth: APP_SEARCH_DEPTH, into: &installed)
        }
        if options.usesSystemTools {
            installed.ids.formUnion(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let launchFolders = SYSTEM_ID_FOLDERS + [(options.home as NSString).appendingPathComponent("Library/LaunchAgents")]
            for folder in launchFolders {
                installed.ids.formUnion(PathTools.children(of: folder).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension })
            }
        }
        return installed
    }

    private static func collectApps(in folder: String, depth: Int, into installed: inout Installed) {
        for path in PathTools.children(of: folder) {
            if path.hasSuffix(".app") {
                let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Contents/Info.plist"))
                let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                var names = [fileName]
                names += ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"].compactMap { info?[$0] as? String }
                if let id = info?["CFBundleIdentifier"] as? String {
                    installed.ids.insert(id)
                    let parts = id.split(separator: ".")
                    if parts.count >= 3 {
                        names += [String(parts[1]), String(parts[parts.count - 1])]
                    }
                }
                installed.names.formUnion(names.map(normalized))
            } else if depth > 1 && PathTools.isDirectory(path) {
                collectApps(in: path, depth: depth - 1, into: &installed)
            }
        }
    }
}
