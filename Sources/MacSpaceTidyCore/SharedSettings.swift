import Foundation

/// Settings shared by the app and the terminal program, in one defaults domain.
public enum SharedSettings {
    public static let SUITE_NAME = "io.github.yanmasharski.MacSpaceTidy.settings"
    private static let DELETE_MODE_KEY = "deleteMode"
    private static let MOVE_DISK_KEY = "moveDiskRoot"

    private static var store: UserDefaults {
        return UserDefaults(suiteName: SUITE_NAME) ?? .standard
    }

    public static var deleteMode: DeleteMode {
        get { store.string(forKey: DELETE_MODE_KEY).flatMap(DeleteMode.init(rawValue:)) ?? .trash }
        set { store.set(newValue.rawValue, forKey: DELETE_MODE_KEY) }
    }

    /// The external disk for moves. Nil until the user picks one.
    public static var moveDiskRoot: String? {
        get { store.string(forKey: MOVE_DISK_KEY) }
        set { store.set(newValue, forKey: MOVE_DISK_KEY) }
    }
}
