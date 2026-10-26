import MacSpaceTidyCore

/// One line of the main list.
enum TuiRow {
    case problem(Problem)
    case category(ItemCategory, [ScanItem])
    /// A category the scan has not counted yet.
    case pending(ItemCategory)
    case item(ScanItem)
    /// One copy of a group of duplicates: the group and the copy's index.
    case copy(ScanItem, Int)
}
