public struct CatalogEntry: Codable, Sendable {
    /// Trailing `/*` means: every child of the folder is a separate item.
    public static let CHILDREN_SUFFIX = "/*"

    public let id: String
    /// Absolute, or starts with `~` for the home folder.
    public let path: String
    public let category: ItemCategory
    public let action: ItemAction
    public let risk: Risk
    public let checkedByDefault: Bool
    public let needsAdmin: Bool
    /// Process names. The owner app must not run during delete or move.
    public let ownerApps: [String]
    public let reason: String
    /// A delete item that may also be moved to an external disk instead.
    public let canMove: Bool

    public var isChildrenPattern: Bool {
        return path.hasSuffix(CatalogEntry.CHILDREN_SUFFIX)
    }

    public init(
        id: String, path: String, category: ItemCategory, action: ItemAction, risk: Risk,
        checkedByDefault: Bool, needsAdmin: Bool, ownerApps: [String], reason: String, canMove: Bool = false
    ) {
        self.id = id
        self.path = path
        self.category = category
        self.action = action
        self.risk = risk
        self.checkedByDefault = checkedByDefault
        self.needsAdmin = needsAdmin
        self.ownerApps = ownerApps
        self.reason = reason
        self.canMove = canMove
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            path: try container.decode(String.self, forKey: .path),
            category: try container.decode(ItemCategory.self, forKey: .category),
            action: try container.decode(ItemAction.self, forKey: .action),
            risk: try container.decode(Risk.self, forKey: .risk),
            checkedByDefault: try container.decode(Bool.self, forKey: .checkedByDefault),
            needsAdmin: try container.decode(Bool.self, forKey: .needsAdmin),
            ownerApps: try container.decode([String].self, forKey: .ownerApps),
            reason: try container.decode(String.self, forKey: .reason),
            canMove: try container.decodeIfPresent(Bool.self, forKey: .canMove) ?? false
        )
    }
}
