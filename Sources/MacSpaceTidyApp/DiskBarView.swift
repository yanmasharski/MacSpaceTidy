import MacSpaceTidyCore
import SwiftUI

/// Used and free space from `df`, split by category.
struct DiskBarView: View {
    private struct Segment: Identifiable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
    }

    private static let BAR_HEIGHT: CGFloat = 22
    private static let LEGEND_COLUMN_WIDTH: CGFloat = 190

    let report: ScanReport

    var body: some View {
        let disk = report.disk
        let segments = makeSegments()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(ByteText.format(disk.usedBytes)) used of \(ByteText.format(disk.totalBytes))")
                    .font(.title3.bold())
                Spacer()
                Text("\(ByteText.format(disk.freeBytes)) free")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        segment.color
                            .frame(width: geometry.size.width * fraction(segment.bytes))
                            .help("\(segment.title): \(ByteText.format(segment.bytes))")
                    }
                }
            }
            .frame(height: DiskBarView.BAR_HEIGHT)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DiskBarView.LEGEND_COLUMN_WIDTH), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.color).frame(width: 9, height: 9)
                        Text(segment.title)
                        Text(ByteText.format(segment.bytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func fraction(_ bytes: Int64) -> CGFloat {
        return CGFloat(bytes) / CGFloat(max(report.disk.totalBytes, 1))
    }

    private func makeSegments() -> [Segment] {
        var segments: [Segment] = []
        var knownBytes: Int64 = 0
        for category in ItemCategory.allCases where category.isOnInternalDisk {
            let bytes = report.totalBytes(in: category)
            guard bytes > 0 else {
                continue
            }
            knownBytes += bytes
            segments.append(Segment(id: category.rawValue, title: category.title, bytes: bytes, color: CategoryColors.color(category)))
        }
        let otherBytes = max(report.disk.usedBytes - knownBytes, 0)
        segments.append(Segment(id: "other", title: "Everything else", bytes: otherBytes, color: CategoryColors.other))
        segments.append(Segment(id: "free", title: "Free", bytes: report.disk.freeBytes, color: CategoryColors.free))
        return segments
    }
}
