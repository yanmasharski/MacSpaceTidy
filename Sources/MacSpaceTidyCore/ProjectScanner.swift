import Foundation

/// Finds build folders of your projects (`node_modules`, `target`, `.build`, …) that the tools create again.
/// A folder counts only when its project has the matching marker file (`package.json` for `node_modules`),
/// so a plain folder named `build` is left alone. Items are never checked by default and always go to the Trash.
///
/// Safety, checked at scan time and again right before the Trash: git tracks nothing inside, no signing key or
/// certificate lies directly inside, it is not a link, and it sits inside one of your project folders.
public enum ProjectScanner {
    private struct Rule {
        let name: String
        /// Files or folders next to it. One of them must exist.
        let markers: [String]
        let what: String
        let rebuild: String
        let risk: Risk
    }

    private static let RULES = [
        Rule(name: "node_modules", markers: ["package.json"], what: "Node packages", rebuild: "npm or yarn installs them again.", risk: .low),
        Rule(name: "dist", markers: ["package.json"], what: "Built web files", rebuild: "Your next build creates them again.", risk: .medium),
        Rule(name: "target", markers: ["Cargo.toml", "pom.xml"], what: "Rust or Maven build output", rebuild: "The next build creates it again.", risk: .low),
        Rule(name: ".build", markers: ["Package.swift"], what: "Swift package build output", rebuild: "The next build creates it again.", risk: .low),
        Rule(name: "build", markers: ["build.gradle", "build.gradle.kts", "CMakeLists.txt"], what: "Build output", rebuild: "The next build creates it again.", risk: .medium),
        Rule(name: "Pods", markers: ["Podfile"], what: "CocoaPods libraries", rebuild: "`pod install` creates them again.", risk: .low),
        Rule(name: "Library", markers: ["ProjectSettings/ProjectVersion.txt"], what: "Unity import cache", rebuild: "Unity imports all assets again when you open the project. That can take long.", risk: .medium),
    ]
    private static let MAX_DEPTH = 5
    /// Never searched inside: build folders hold copies of other projects.
    private static let SKIP_DESCENT: Set<String> = ["node_modules", "Pods", "target", "build", "dist", "Library", "bower_components", "DerivedData"]
    private static let KEY_EXTENSIONS: Set<String> = ["pem", "p12", "pfx", "jks", "keystore", "key", "mobileprovision"]
    private static let GIT = "/usr/bin/git"
    private static let XCODE_SELECT = "/usr/bin/xcode-select"
    private static let GIT_TIMEOUT_SECONDS = 30.0
    private static let SECONDS_PER_DAY: TimeInterval = 86_400
    /// `/usr/bin/git` is a stub that opens an install dialog when the developer tools are missing, so ask first.
    private static let isGitInstalled = CommandRunner.run(XCODE_SELECT, ["-p"], timeoutSeconds: 5)?.exitCode == 0

    /// Folders searched for projects: the usual ones plus the lines of `project-roots.txt`. Only folders on the
    /// internal disk inside your home folder (or `/Users/Shared`) count, because that is all the tool may clean.
    public static func roots(options: ScanOptions) -> [String] {
        let listed = PathListFile.read(at: options.projectRootsPath, home: options.home) ?? []
        let allowed = [PathTools.resolved(options.home), Mover.SHARED_USERS_FOLDER]
        var seen = Set<String>()
        var result: [String] = []
        for root in options.projectRoots + listed {
            let real = PathTools.resolved(root)
            if PathTools.isDirectory(real), !options.disks.isOnExternalDisk(real),
               allowed.contains(where: { PathTools.isSameOrInside(real, folder: $0) && real != $0 }), seen.insert(real).inserted {
                result.append(real)
            }
        }
        return result
    }

    public static func items(options: ScanOptions, now: Date = Date(), progress: Scanner.Progress? = nil) -> [ScanItem] {
        var result: [ScanItem] = []
        for root in roots(options: options) {
            for (path, rule) in artifacts(in: root, depth: MAX_DEPTH) {
                progress?(PathTools.abbreviate(path, home: options.home))
                let size = FolderSize.measure(path: path)
                guard size.bytes >= options.projectMinBytes, refusal(path, options: options) == nil else {
                    continue
                }
                result.append(ScanItem(
                    path: path, title: PathTools.abbreviate(path, home: options.home), catalogId: nil, category: .projects,
                    action: .trashOnly, risk: rule.risk, checkedByDefault: false, needsAdmin: false, ownerApps: [],
                    reason: reason(rule, project: ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent, size: size, now: now),
                    size: size, linkTarget: nil
                ))
            }
        }
        return result.sorted { $0.size.bytes > $1.size.bytes }
    }

    /// Nil when the folder may go to the Trash. Run again by the Optimizer right before it does.
    public static func refusal(_ path: String, options: ScanOptions) -> String? {
        let real = PathTools.resolved(path)
        guard rule(for: path) != nil, !PathTools.isSymlink(path), PathTools.isDirectory(path),
              roots(options: options).contains(where: { PathTools.isSameOrInside(real, folder: $0) && real != $0 }) else {
            return "Not a build folder of a project in your project folders."
        }
        if hasKeyFile(path) {
            return "It holds a signing key or a certificate."
        }
        return gitRefusal(path)
    }

    private static func rule(for path: String) -> Rule? {
        let name = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        return RULES.first { rule in
            rule.name == name && rule.markers.contains { PathTools.exists((parent as NSString).appendingPathComponent($0)) }
        }
    }

    private static func artifacts(in folder: String, depth: Int) -> [(path: String, rule: Rule)] {
        var found: [(path: String, rule: Rule)] = []
        for path in PathTools.children(of: folder) where PathTools.isDirectory(path) && !PathTools.isSymlink(path) {
            if let rule = rule(for: path) {
                found.append((path, rule))
                continue
            }
            let name = (path as NSString).lastPathComponent
            if depth > 0 && !name.hasPrefix(".") && !SKIP_DESCENT.contains(name) {
                found += artifacts(in: path, depth: depth - 1)
            }
        }
        return found
    }

    private static func hasKeyFile(_ path: String) -> Bool {
        return PathTools.children(of: path).contains { KEY_EXTENSIONS.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// A project outside git has nothing to check. Inside git, git must answer, and no file inside may be tracked.
    private static func gitRefusal(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        guard isInsideGitRepository(parent) else {
            return nil
        }
        guard isGitInstalled,
              let result = CommandRunner.run(GIT, ["-C", parent, "ls-files", "--", (path as NSString).lastPathComponent], timeoutSeconds: GIT_TIMEOUT_SECONDS),
              result.exitCode == 0 else {
            return "Git did not answer, so tracked files could not be checked."
        }
        return result.output.isEmpty ? nil : "Git tracks files inside it."
    }

    private static func isInsideGitRepository(_ folder: String) -> Bool {
        var current = folder
        while current != "/" && !current.isEmpty {
            if PathTools.exists((current as NSString).appendingPathComponent(".git")) {
                return true
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return false
    }

    private static func reason(_ rule: Rule, project: String, size: FolderSize, now: Date) -> String {
        var text = "\(rule.what) of \(project). \(rule.rebuild)"
        guard let changed = size.newestChange else {
            return text
        }
        let days = Int(now.timeIntervalSince(changed) / SECONDS_PER_DAY)
        text += days < 1 ? " Changed today: a build may be running." : " Last changed \(days) days ago."
        return text
    }
}
