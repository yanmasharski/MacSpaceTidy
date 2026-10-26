import MacSpaceTidyCore

/// Text helpers for the terminal interface. Widths count characters; wide characters are rare in paths.
enum TuiText {
    static let RESET = "\u{1B}[0m"
    static let BOLD = "\u{1B}[1m"
    static let DIM = "\u{1B}[2m"
    static let INVERSE = "\u{1B}[7m"
    static let RED = "\u{1B}[31m"
    static let GREEN = "\u{1B}[32m"
    static let YELLOW = "\u{1B}[33m"
    static let BLUE = "\u{1B}[34m"
    static let MAGENTA = "\u{1B}[35m"
    private static let ELLIPSIS = "…"
    private static let OTHER_COLOR = 240
    private static let FREE_COLOR = 236

    /// 256-color codes, close to the app's category colors.
    static func colorCode(_ category: ItemCategory) -> Int {
        switch category {
        case .caches: return 33
        case .developer: return 99
        case .apps: return 208
        case .downloads: return 178
        case .leftovers: return 175
        case .projects: return 72
        case .simulators: return 205
        case .cleanInApp: return 37
        case .largeUnknown: return 137
        case .duplicates: return 79
        case .alreadyMoved: return 71
        case .external: return 62
        case .system: return 245
        }
    }

    static func foreground(_ code: Int) -> String {
        return "\u{1B}[38;5;\(code)m"
    }

    static func background(_ code: Int) -> String {
        return "\u{1B}[48;5;\(code)m"
    }

    static var otherColor: Int {
        return OTHER_COLOR
    }

    static var freeColor: Int {
        return FREE_COLOR
    }

    static func fit(_ text: String, _ width: Int) -> String {
        guard width > 0 else {
            return ""
        }
        if text.count <= width {
            return text + String(repeating: " ", count: width - text.count)
        }
        return String(text.prefix(width - 1)) + ELLIPSIS
    }

    /// Cuts the middle, so both the start and the end of a path stay visible.
    static func fitMiddle(_ text: String, _ width: Int) -> String {
        guard text.count > width, width > 3 else {
            return fit(text, width)
        }
        let head = (width - 1) / 2
        let tail = width - 1 - head
        return String(text.prefix(head)) + ELLIPSIS + String(text.suffix(tail))
    }

    static func padLeft(_ text: String, _ width: Int) -> String {
        return String(repeating: " ", count: max(0, width - text.count)) + text
    }
}
