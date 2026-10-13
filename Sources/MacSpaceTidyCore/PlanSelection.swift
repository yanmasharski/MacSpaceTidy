import Foundation

/// What the user chose: checked items, and which "move or delete" items are set to Move.
/// Shared by the app and the terminal interface.
public struct PlanSelection: Sendable, Equatable {
    public var selected: Set<String> = []
    public var chosenMoves: Set<String> = []

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

    /// Safe items are checked, except app caches used in the last days. With a disk, moving is preferred over deleting.
    public static func defaults(for items: [ScanItem], hasDisk: Bool, now: Date = Date()) -> PlanSelection {
        var plan = PlanSelection()
        plan.selected = Set(items.filter { $0.checkedByDefault && isSelectable($0) && !isRecentlyUsed($0, now: now) }.map(\.id))
        if hasDisk {
            plan.preferMoves(in: items)
        }
        return plan
    }

    public func isSelected(_ item: ScanItem) -> Bool {
        return selected.contains(item.id)
    }

    public func effectiveAction(_ item: ScanItem, hasDisk: Bool) -> ItemAction {
        return item.canMove && hasDisk && chosenMoves.contains(item.id) ? .move : item.action
    }

    /// Checked items, each with the action the user chose.
    public func chosenItems(from items: [ScanItem], hasDisk: Bool) -> [ScanItem] {
        return items.filter(isSelected).map { item in
            effectiveAction(item, hasDisk: hasDisk) == item.action ? item : item.with(action: .move)
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
