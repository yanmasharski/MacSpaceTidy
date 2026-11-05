import Foundation

/// Settings shared by the app and the terminal program, in one defaults domain.
public enum SharedSettings {
    public static let SUITE_NAME = "io.github.yanmasharski.MacSpaceTidy.settings"
    private static let DELETE_MODE_KEY = "deleteMode"
    private static let MOVE_DISK_KEY = "moveDiskRoot"
    private static let EXTRA_SCAN_DISKS_KEY = "extraScanDisks"
    private static let DUPLICATE_SCAN_DISKS_KEY = "duplicateScanDisks"

    private static var store: UserDefaults {
        return UserDefaults(suiteName: SUITE_NAME) ?? .standard
    }

    public static var deleteMode: DeleteMode {
        get { store.string(forKey: DELETE_MODE_KEY).flatMap(DeleteMode.init(rawValue:)) ?? .trash }
        set { store.set(newValue.rawValue, forKey: DELETE_MODE_KEY) }
    }

    /// External disks (`/Volumes/<name>`) the user chose to search for large files. None until chosen.
    public static var extraScanDisks: [String] {
        get { store.stringArray(forKey: EXTRA_SCAN_DISKS_KEY) ?? [] }
        set { store.set(newValue, forKey: EXTRA_SCAN_DISKS_KEY) }
    }

    /// External disks the user chose for the duplicate search. None until chosen.
    public static var duplicateScanDisks: [String] {
        get { store.stringArray(forKey: DUPLICATE_SCAN_DISKS_KEY) ?? [] }
        set { store.set(newValue, forKey: DUPLICATE_SCAN_DISKS_KEY) }
    }

    /// The external disk for moves. Nil until the user picks one.
    public static var moveDiskRoot: String? {
        get { store.string(forKey: MOVE_DISK_KEY) }
        set { store.set(newValue, forKey: MOVE_DISK_KEY) }
    }
}
