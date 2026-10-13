import MacSpaceTidyCore
import SwiftUI

/// Small bar for an external disk: what was moved there from this Mac, everything else, and free space.
struct ExternalDiskBarView: View {
    private static let BAR_HEIGHT: CGFloat = 10

    let disk: ExternalDiskUsage

    var body: some View {
        let total = CGFloat(max(disk.space.totalBytes, 1))
        let otherBytes = max(disk.space.usedBytes - disk.movedBytes, 0)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill").foregroundStyle(.secondary)
                Text(disk.name).font(.headline)
                Text("\(ByteText.format(disk.space.usedBytes)) used of \(ByteText.format(disk.space.totalBytes)), \(ByteText.format(disk.space.freeBytes)) free")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(CategoryColors.color(.alreadyMoved)).frame(width: 8, height: 8)
                    Text("Moved from this Mac: \(ByteText.format(disk.movedBytes))")
                }
                .font(.callout)
            }
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    CategoryColors.color(.alreadyMoved).frame(width: geometry.size.width * CGFloat(disk.movedBytes) / total)
                    CategoryColors.other.frame(width: geometry.size.width * CGFloat(otherBytes) / total)
                    CategoryColors.free
                }
            }
            .frame(height: ExternalDiskBarView.BAR_HEIGHT)
            .clipShape(Capsule())
        }
    }
}
