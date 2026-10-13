import MacSpaceTidyCore
import SwiftUI

struct RiskBadgeView: View {
    let risk: Risk

    var body: some View {
        if risk != .low {
            Text(risk == .medium ? "medium risk" : "high risk")
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(color)
                .background(color.opacity(0.15), in: Capsule())
        }
    }

    private var color: Color {
        return risk == .medium ? .orange : .red
    }
}
