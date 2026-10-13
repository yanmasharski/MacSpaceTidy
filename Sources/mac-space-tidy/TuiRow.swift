import MacSpaceTidyCore

/// One line of the main list.
enum TuiRow {
    case problem(Problem)
    case category(ItemCategory, [ScanItem])
    case item(ScanItem)
}
