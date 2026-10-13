import AppKit

public enum RunningApps {
    /// Name of a running app that owns the item, or nil.
    /// Cache folders are often named by bundle id (`ru.keepcoder.Telegram`), so the folder name is checked too.
    public static func owner(of item: ScanItem) -> String? {
        let folderName = (item.path as NSString).lastPathComponent
        let names = Set(item.ownerApps + [folderName])
        for app in NSWorkspace.shared.runningApplications {
            let candidates = [app.localizedName, app.bundleIdentifier, app.executableURL?.lastPathComponent].compactMap { $0 }
            if candidates.contains(where: names.contains) {
                return app.localizedName ?? folderName
            }
        }
        return item.ownerApps.first(where: ProcessCheck.isRunning)
    }

    /// Asks the app to quit, like Cmd-Q. Returns false when no such app runs.
    @discardableResult
    public static func quit(named name: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName == name }
        apps.forEach { $0.terminate() }
        return !apps.isEmpty
    }
}
