import Foundation

/// What the user chose: checked items, and which "move or delete" items are set to Move.
/// Shared by the app and the terminal interface.
public struct PlanSelection: Sendable, Equatable {
    public var selected: Set<String> = []
    public var chosenMoves: Set<String> = []
    /// For a group of duplicates: the index of the copy that stays. The first (suggested) copy when missing.
    public var keepers: [String: Int] = [:]

    public init() {}

    public static func isSelectable(_ item: ScanItem) -> Bool {
        switch item.action {
        case .delete, .deleteSimulatorRuntime, .move, .cleanExternal, .deleteExternalCopy, .trashOnly:
            return true
        case .moveBack, .cleanInApp, .info, .never:
            return false
        }
    }

    /// An app cache that changed within this time may be in use, so it is not checked by default.
    public static let RECENT_SECONDS: TimeInterval = 2 * 24 * 60 * 60

    public static func isRecentlyUsed(_ item: ScanItem, now: Date = Date()) -> Bool {
        guard item.ageMatters, let changed = item.size.newestChange else {
            return false
        }
        return now.timeIntervalSince(changed) < RECENT_SECONDS
    }

    /// Safe items are checked, except app caches used in the last days. Moving is preferred over deleting.
    /// Without a disk the move is skipped when the plan runs; nothing is deleted instead.
    public static func defaults(for items: [ScanItem], now: Date = Date()) -> PlanSelection {
        var plan = PlanSelection()
        plan.selected = Set(items.filter { $0.checkedByDefault && isSelectable($0) && !isRecentlyUsed($0, now: now) }.map(\.id))
        plan.preferMoves(in: items)
        return plan
    }

    /// Adds the defaults for items that arrived later (a scan block). Earlier choices of the user stay.
    public mutating func addDefaults(for newItems: [ScanItem], now: Date = Date()) {
        let fresh = PlanSelection.defaults(for: newItems, now: now)
        selected.formUnion(fresh.selected)
        chosenMoves.formUnion(fresh.chosenMoves)
    }

    public func isSelected(_ item: ScanItem) -> Bool {
        return selected.contains(item.id)
    }

    public func effectiveAction(_ item: ScanItem) -> ItemAction {
        return item.canMove && chosenMoves.contains(item.id) ? .move : item.action
    }

    /// Checked items, each with the action the user chose.
    public func chosenItems(from items: [ScanItem]) -> [ScanItem] {
        return items.filter(isSelected).flatMap { item -> [ScanItem] in
            if item.category == .duplicates {
                return removals(of: item)
            }
            return [effectiveAction(item) == item.action ? item : item.with(action: .move)]
        }
    }

    public func keeperIndex(of group: ScanItem) -> Int {
        return min(max(keepers[group.id] ?? 0, 0), max(group.duplicateCopies.count - 1, 0))
    }

    public mutating func setKeeper(of group: ScanItem, to index: Int) {
        keepers[group.id] = index
    }

    /// The copies of a checked group that go to the Trash: all but the one that stays.
    public func removals(of group: ScanItem) -> [ScanItem] {
        guard !group.duplicateCopies.isEmpty else {
            return []
        }
        let keeperIndex = keeperIndex(of: group)
        let keeper = group.duplicateCopies[keeperIndex].path
        return group.duplicateCopies.enumerated().filter { $0.offset != keeperIndex }.map { _, copy in
            ScanItem(
                path: copy.path, title: PathTools.abbreviate(copy.path, home: NSHomeDirectory()), catalogId: nil, category: .duplicates,
                action: .trashOnly, risk: .medium, checkedByDefault: false, needsAdmin: false, ownerApps: [], reason: group.reason,
                size: FolderSize(bytes: copy.bytes, isIncomplete: false, newestChange: copy.modified), linkTarget: nil, keeperPath: keeper
            )
        }
    }

    public mutating func toggle(_ item: ScanItem) {
        guard PlanSelection.isSelectable(item) else {
            return
        }
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
    }

    public mutating func setSelected(_ items: [ScanItem], _ isSelected: Bool) {
        let ids = items.filter(PlanSelection.isSelectable).map(\.id)
        if isSelected {
            selected.formUnion(ids)
        } else {
            selected.subtract(ids)
        }
    }

    public mutating func setMove(_ item: ScanItem, _ isMove: Bool) {
        if isMove {
            chosenMoves.insert(item.id)
        } else {
            chosenMoves.remove(item.id)
        }
    }

    public mutating func preferMoves(in items: [ScanItem]) {
        chosenMoves.formUnion(items.filter(\.canMove).map(\.id))
    }
}
