import MacSpaceTidyCore
import SwiftUI

enum CategoryColors {
    static let other = Color.gray.opacity(0.35)
    static let free = Color.primary.opacity(0.06)

    static func color(_ category: ItemCategory) -> Color {
        switch category {
        case .caches: return .blue
        case .developer: return .purple
        case .apps: return .orange
        case .downloads: return .yellow
        case .simulators: return .pink
        case .cleanInApp: return .teal
        case .largeUnknown: return .brown
        case .alreadyMoved: return .green
        case .external: return .indigo
        case .system: return .gray
        }
    }
}
