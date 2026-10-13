public enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case caches
    case developer
    case apps
    case simulators
    case cleanInApp
    case largeUnknown
    case alreadyMoved
    case external
    case system

    public var title: String {
        switch self {
        case .caches: return "Caches"
        case .developer: return "Developer tools"
        case .apps: return "Apps"
        case .simulators: return "Simulator runtimes"
        case .cleanInApp: return "Clean inside the app"
        case .largeUnknown: return "Large, unknown"
        case .alreadyMoved: return "Already moved"
        case .external: return "Clean on external disk"
        case .system: return "System"
        }
    }

    /// Takes space on the internal disk, so it is a segment of the disk bar.
    public var isOnInternalDisk: Bool {
        return self != .alreadyMoved && self != .external && self != .system
    }
}
