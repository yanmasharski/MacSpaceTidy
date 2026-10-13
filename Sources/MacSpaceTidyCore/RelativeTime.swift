import Foundation

public enum RelativeTime {
    /// "2 hours ago", "yesterday".
    public static func ago(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
