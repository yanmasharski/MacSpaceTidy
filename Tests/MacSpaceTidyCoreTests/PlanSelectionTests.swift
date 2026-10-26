import Foundation
import Testing
@testable import MacSpaceTidyCore

struct PlanSelectionTests {
    private func item(
        _ id: String, action: ItemAction, checked: Bool, canMove: Bool = false, ageMatters: Bool = false, changed: Date? = nil
    ) -> ScanItem {
        return ScanItem(
            path: id, title: id, catalogId: nil, category: .caches, action: action, risk: .low,
            checkedByDefault: checked, needsAdmin: false, ownerApps: [], reason: "test",
            size: FolderSize(bytes: 1, isIncomplete: false, newestChange: changed), linkTarget: nil, canMove: canMove, ageMatters: ageMatters
        )
    }

    @Test func doesNotCheckAppCachesUsedInTheLastTwoDays() {
        let now = Date()
        let items = [
            item("fresh-app-cache", action: .delete, checked: true, ageMatters: true, changed: now.addingTimeInterval(-3600)),
            item("old-app-cache", action: .delete, checked: true, ageMatters: true, changed: now.addingTimeInterval(-5 * 86_400)),
            item("fresh-download-cache", action: .delete, checked: true, ageMatters: false, changed: now.addingTimeInterval(-3600)),
            item("empty-app-cache", action: .delete, checked: true, ageMatters: true, changed: nil),
        ]

        let plan = PlanSelection.defaults(for: items, now: now)

        #expect(plan.selected == ["old-app-cache", "fresh-download-cache", "empty-app-cache"])
    }

    @Test func prefersMoveAndKeepsItWithoutDisk() {
        let items = [
            item("cache", action: .delete, checked: true, canMove: true),
            item("small", action: .delete, checked: true),
            item("moved", action: .moveBack, checked: true),
        ]

        var plan = PlanSelection.defaults(for: items)

        #expect(plan.selected == ["cache", "small"])
        #expect(plan.chosenItems(from: items).map(\.action) == [.move, .delete])

        plan.setMove(items[0], false)
        #expect(plan.chosenItems(from: items).map(\.action) == [.delete, .delete])
    }

    @Test func offersManualMoveForBigItemsWithoutTheirOwnMoveOption() {
        func make(_ category: ItemCategory, _ action: ItemAction, bytes: Int64, canMove: Bool = false, admin: Bool = false) -> ScanItem {
            return ScanItem(
                path: "p", title: "p", catalogId: nil, category: category, action: action, risk: .low,
                checkedByDefault: false, needsAdmin: admin, ownerApps: [], reason: "test",
                size: FolderSize(bytes: bytes, isIncomplete: false), linkTarget: nil, canMove: canMove
            )
        }
        let big: Int64 = 2_000_000_000

        #expect(make(.caches, .delete, bytes: big).offersManualMove)
        #expect(make(.largeUnknown, .info, bytes: 5).offersManualMove)
        #expect(!make(.caches, .delete, bytes: 500_000_000).offersManualMove)
        #expect(!make(.developer, .delete, bytes: big, canMove: true).offersManualMove)
        #expect(!make(.developer, .delete, bytes: big, admin: true).offersManualMove)
        #expect(!make(.alreadyMoved, .moveBack, bytes: big).offersManualMove)
    }

    @Test func togglesOnlySelectableItems() {
        let moved = item("moved", action: .moveBack, checked: false)
        var plan = PlanSelection()

        plan.toggle(moved)

        #expect(plan.selected.isEmpty)
    }
}
