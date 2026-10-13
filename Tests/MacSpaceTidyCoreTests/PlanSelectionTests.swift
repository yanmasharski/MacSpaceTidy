import Testing
@testable import MacSpaceTidyCore

struct PlanSelectionTests {
    private func item(_ id: String, action: ItemAction, checked: Bool, canMove: Bool = false) -> ScanItem {
        return ScanItem(
            path: id, title: id, catalogId: nil, category: .caches, action: action, risk: .low,
            checkedByDefault: checked, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize(bytes: 1, isIncomplete: false), linkTarget: nil, canMove: canMove
        )
    }

    @Test func prefersMoveOnlyWhenDiskIsSet() {
        let items = [
            item("cache", action: .delete, checked: true, canMove: true),
            item("small", action: .delete, checked: true),
            item("moved", action: .moveBack, checked: true),
        ]

        let withDisk = PlanSelection.defaults(for: items, hasDisk: true)
        let withoutDisk = PlanSelection.defaults(for: items, hasDisk: false)

        #expect(withDisk.selected == ["cache", "small"])
        #expect(withDisk.chosenItems(from: items, hasDisk: true).map(\.action) == [.move, .delete])
        #expect(withoutDisk.chosenItems(from: items, hasDisk: false).map(\.action) == [.delete, .delete])
    }

    @Test func togglesOnlySelectableItems() {
        let moved = item("moved", action: .moveBack, checked: false)
        var plan = PlanSelection()

        plan.toggle(moved)

        #expect(plan.selected.isEmpty)
    }
}
