public enum ItemAction: String, Codable, Sendable {
    case delete
    case move
    case deleteSimulatorRuntime
    /// Copy an already moved folder back to the internal disk.
    case moveBack
    /// Empty a cache on an external disk. The folder and its link stay.
    case cleanExternal
    /// One of your own files (a download). Always goes to the Trash, whatever the delete setting is.
    case trashOnly
    /// Delete a whole copy in the tool folder on an external disk that nothing links to.
    case deleteExternalCopy
    case cleanInApp
    /// Shown for information only. A manual move is possible with a warning.
    case info
    case never
}
