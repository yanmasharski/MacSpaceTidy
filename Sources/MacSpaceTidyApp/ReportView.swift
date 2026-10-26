import AppKit
import MacSpaceTidyCore
import SwiftUI

/// The scan result: disk bars, banners, problems, and the category list.
struct ReportView: View {
    private static let FULL_DISK_ACCESS_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    let model: AppModel
    let report: ScanReport
    /// False for snapshots, which render the whole height at once.
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            DiskBarView(report: report)
            ForEach(report.externalDisks) { disk in
                ExternalDiskBarView(disk: disk)
            }
            banners
            if !report.problems.filter({ $0.kind != .lowFreeSpace }).isEmpty {
                ProblemsView(model: model, problems: report.problems)
            }
            CategoryListView(model: model, report: report)
            ScanDisksView(model: model)
        }
        .padding(20)
    }

    @ViewBuilder
    private var banners: some View {
        if let lowSpace = report.problems.first(where: { $0.kind == .lowFreeSpace }) {
            BannerView(systemImage: "exclamationmark.triangle.fill", tint: .red, text: lowSpace.detail)
        }
        if report.hasUnreadableFolders {
            BannerView(systemImage: "lock.fill", tint: .orange, text: "Some folders could not be read. Give Full Disk Access for full numbers.") {
                Button("Open Settings") {
                    if let url = URL(string: ReportView.FULL_DISK_ACCESS_URL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
