public enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case caches
    case developer
    case apps
    case downloads
    case leftovers
    case projects
    case simulators
    case cleanInApp
    case largeUnknown
    case duplicates
    case alreadyMoved
    case external
    case system

    public var title: String {
        switch self {
        case .caches: return "Caches"
        case .developer: return "Developer tools"
        case .apps: return "Apps"
        case .downloads: return "Downloads"
        case .leftovers: return "Leftovers of removed apps"
        case .projects: return "Project build folders"
        case .simulators: return "Simulator runtimes"
        case .cleanInApp: return "Clean inside the app"
        case .largeUnknown: return "Large files and folders"
        case .duplicates: return "Duplicate files"
        case .alreadyMoved: return "Already moved"
        case .external: return "Clean on external disk"
        case .system: return "System"
        }
    }

    /// Takes space on the internal disk, so it is a segment of the disk bar.
    public var isOnInternalDisk: Bool {
        // Duplicates are counted already in the categories and folders they sit in.
        return self != .alreadyMoved && self != .external && self != .system && self != .duplicates
    }
}
