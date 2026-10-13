import Foundation
import MacSpaceTidyCore

/// Made-up data for README screenshots. Nothing here comes from a real Mac.
@MainActor
enum DemoData {
    private static let GB: Int64 = 1_000_000_000
    private static let MB: Int64 = 1_000_000
    private static let DISK_ROOT = "/Volumes/Backup SSD"
    private static let DAY: TimeInterval = 86_400

    static func configure(_ model: AppModel) {
        let report = makeReport()
        model.isDemo = true
        model.report = report
        model.diskChoices = [DiskChoice(path: DISK_ROOT, name: "Backup SSD", fileSystem: "apfs", freeBytes: 520 * GB, problem: nil)]
        model.moveDiskRoot = DISK_ROOT
        model.plan = PlanSelection.defaults(for: report.items, hasDisk: true)
        model.initiallyExpanded = [.downloads, .developer]
    }

    private static func item(
        _ title: String, _ category: ItemCategory, _ action: ItemAction, _ bytes: Int64, risk: Risk = .low, checked: Bool = false,
        admin: Bool = false, canMove: Bool = false, ageMatters: Bool = false, changedDaysAgo: Double? = nil, target: String? = nil,
        reason: String
    ) -> ScanItem {
        let changed = changedDaysAgo.map { Date().addingTimeInterval(-$0 * DAY) }
        return ScanItem(
            path: title.hasPrefix("~") ? "/Users/demo" + title.dropFirst() : title, title: title, catalogId: nil, category: category,
            action: action, risk: risk, checkedByDefault: checked, needsAdmin: admin, ownerApps: [], reason: reason,
            size: FolderSize(bytes: bytes, isIncomplete: false, newestChange: changed), linkTarget: target, canMove: canMove, ageMatters: ageMatters
        )
    }

    private static func makeReport() -> ScanReport {
        let moved = DISK_ROOT + "/MacSpaceTidy/Users/demo"
        let items = [
            item("~/Library/Caches/Homebrew", .caches, .delete, 1_350 * MB, checked: true, ageMatters: true, changedDaysAgo: 12, reason: "Downloaded Homebrew packages. Homebrew downloads them again when needed."),
            item("~/Library/Caches/Spotify", .caches, .delete, 612 * MB, checked: true, ageMatters: true, changedDaysAgo: 0.2, reason: "App cache. The app rebuilds it. Quit the app first."),
            item("~/Library/Caches/com.example.Notes", .caches, .delete, 331 * MB, checked: true, ageMatters: true, changedDaysAgo: 40, reason: "App cache. The app rebuilds it. Quit the app first."),
            item("~/Library/Caches/pip", .caches, .delete, 118 * MB, checked: true, ageMatters: true, changedDaysAgo: 30, reason: "App cache. The app rebuilds it. Quit the app first."),
            item("~/Library/Developer/Xcode/DerivedData", .developer, .delete, 9_800 * MB, checked: true, canMove: true, changedDaysAgo: 3, reason: "Xcode build output. Xcode rebuilds it on the next build."),
            item("~/Library/Developer/Xcode/iOS DeviceSupport", .developer, .delete, 17_800 * MB, checked: true, canMove: true, changedDaysAgo: 60, reason: "Debug symbols for connected iPhones. Xcode copies them again when you connect a device."),
            item("~/.cargo/registry", .developer, .delete, 3_100 * MB, checked: true, canMove: true, changedDaysAgo: 9, reason: "Downloaded Rust crates. Cargo downloads them again."),
            item("~/.gradle/caches", .developer, .delete, 4_200 * MB, checked: true, canMove: true, changedDaysAgo: 20, reason: "Gradle dependency and build cache. Gradle downloads it again."),
            item("/Library/Developer/CoreSimulator/Caches", .developer, .delete, 3_800 * MB, admin: true, reason: "System cache of iOS simulators. The system rebuilds it. Needs the admin password."),
            item("~/Downloads/screen-recording.mp4", .downloads, .trashOnly, 1_200 * MB, risk: .medium, canMove: true, changedDaysAgo: 210, reason: DownloadsScanner.reason(kind: .other, days: 210)),
            item("~/Downloads/Installer-3.2.dmg", .downloads, .trashOnly, 640 * MB, risk: .medium, canMove: true, changedDaysAgo: 75, reason: DownloadsScanner.reason(kind: .installer, days: 75)),
            item("~/Downloads/old-dataset.zip", .downloads, .trashOnly, 380 * MB, risk: .medium, canMove: true, changedDaysAgo: 140, reason: DownloadsScanner.reason(kind: .archive, days: 140)),
            item("~/Library/Application Support/Steam", .apps, .move, 14 * GB, reason: "Steam data and games. Works from an external disk. Quit Steam first."),
            item("~/Library/Application Support/com.example.WineBottles", .apps, .move, 6_500 * MB, risk: .medium, reason: "Wine bottles. Large. Move, do not delete: it holds installed Windows apps."),
            item("iOS 18.5 (22F77)", .simulators, .deleteSimulatorRuntime, 8_840 * MB, risk: .medium, reason: "iOS simulator runtime. Keep the versions you test on. Xcode can download it again."),
            item("iOS 26.0 (23A340)", .simulators, .deleteSimulatorRuntime, 8_070 * MB, risk: .medium, reason: "iOS simulator runtime. Keep the versions you test on. Xcode can download it again."),
            item("~/Library/Containers", .cleanInApp, .cleanInApp, 9_160 * MB, risk: .high, reason: "Data of sandboxed apps. Deleting it breaks apps. Clean it inside each app or uninstall the app."),
            item("~/Library/Mail", .cleanInApp, .cleanInApp, 3_040 * MB, risk: .high, reason: "Mail messages. Remove accounts or mailboxes in the Mail app."),
            item("~/Projects/old-renders", .largeUnknown, .info, 11_600 * MB, risk: .high, reason: "Large folder not in the catalog. Check what it is before you delete or move it."),
            item("~/Movies", .largeUnknown, .info, 6_200 * MB, risk: .high, reason: "Large folder not in the catalog. Check what it is before you delete or move it."),
            item("~/.cache/uv", .alreadyMoved, .moveBack, 38_470 * MB, changedDaysAgo: 2, target: moved + "/.cache/uv", reason: "Already moved to an external disk. You can move it back."),
            item("~/Library/Application Support/Cursor", .alreadyMoved, .moveBack, 21_600 * MB, changedDaysAgo: 0.1, target: moved + "/Library/Application Support/Cursor", reason: "Already moved to an external disk. You can move it back."),
            item("~/.android", .alreadyMoved, .moveBack, 19_300 * MB, changedDaysAgo: 160, target: moved + "/.android", reason: "Already moved to an external disk. You can move it back."),
            item("~/.npm", .alreadyMoved, .moveBack, 14_150 * MB, changedDaysAgo: 5, target: moved + "/.npm", reason: "Already moved to an external disk. You can move it back."),
            item("~/.cache/uv", .external, .cleanExternal, 38_470 * MB, changedDaysAgo: 2, reason: "Cache on the external disk. Cleaning deletes what is inside; the folder and its link stay."),
            item("~/.npm", .external, .cleanExternal, 14_150 * MB, changedDaysAgo: 5, reason: "Cache on the external disk. Cleaning deletes what is inside; the folder and its link stay."),
            item("\(DISK_ROOT)/MacSpaceTidy/Users/demo/Old Project", .external, .deleteExternalCopy, 3_900 * MB, risk: .medium, reason: "Copy on the external disk that nothing links to (for example after Move back). Delete it when you no longer need it."),
        ]
        let problems = [
            Problem(kind: .strayNestedLink, path: NSHomeDirectory() + "/Library/Caches/Caches", detail: "Link inside a folder with the same name. A move did not finish. Data at \(moved)/Library/Caches stays."),
            Problem(kind: .timeMachineSnapshots, path: nil, detail: "2 local Time Machine snapshot(s). They can hold space after you delete files."),
        ]
        let external = ExternalDiskUsage(
            root: DISK_ROOT, space: DiskSpace(totalBytes: 1_000 * GB, freeBytes: 520 * GB), movedBytes: 93 * GB
        )
        return ScanReport(
            disk: DiskSpace(totalBytes: 245 * GB, freeBytes: 38 * GB), items: items.sorted { $0.size.bytes > $1.size.bytes },
            problems: problems, externalDisks: [external]
        )
    }
}
