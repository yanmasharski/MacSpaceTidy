public struct ScanItem: Sendable, Identifiable {
    /// File path, or a `simctl:` id for a simulator runtime.
    public let path: String
    /// Short name for the UI: the path with `~`, or the runtime name.
    public let title: String
    public let catalogId: String?
    public let category: ItemCategory
    public let action: ItemAction
    public let risk: Risk
    public let checkedByDefault: Bool
    public let needsAdmin: Bool
    public let ownerApps: [String]
    public let reason: String
    public let size: FolderSize
    /// Set for already moved items: where the link points.
    public let linkTarget: String?
    /// A delete item that the user may move instead.
    public let canMove: Bool

    public init(
        path: String, title: String, catalogId: String?, category: ItemCategory, action: ItemAction, risk: Risk,
        checkedByDefault: Bool, needsAdmin: Bool, ownerApps: [String], reason: String, size: FolderSize,
        linkTarget: String?, canMove: Bool = false
    ) {
        self.path = path
        self.title = title
        self.catalogId = catalogId
        self.category = category
        self.action = action
        self.risk = risk
        self.checkedByDefault = checkedByDefault
        self.needsAdmin = needsAdmin
        self.ownerApps = ownerApps
        self.reason = reason
        self.size = size
        self.linkTarget = linkTarget
        self.canMove = canMove
    }

    public var id: String {
        return path
    }

    /// The same item with another action. Used for a manual move of an unknown folder.
    public func with(action: ItemAction) -> ScanItem {
        return ScanItem(
            path: path, title: title, catalogId: catalogId, category: category, action: action, risk: risk,
            checkedByDefault: false, needsAdmin: needsAdmin, ownerApps: ownerApps, reason: reason, size: size,
            linkTarget: linkTarget, canMove: canMove
        )
    }

    /// The same item with a new measured size.
    public func with(size: FolderSize) -> ScanItem {
        return ScanItem(
            path: path, title: title, catalogId: catalogId, category: category, action: action, risk: risk,
            checkedByDefault: checkedByDefault, needsAdmin: needsAdmin, ownerApps: ownerApps, reason: reason, size: size,
            linkTarget: linkTarget, canMove: canMove
        )
    }
}
