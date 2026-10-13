import AppKit
import MacSpaceTidyCore
import SwiftUI

struct ContentView: View {
    private static let FULL_DISK_ACCESS_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let report = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DiskBarView(report: report)
                        ForEach(report.externalDisks) { disk in
                            ExternalDiskBarView(disk: disk)
                        }
                        banners(report)
                        if !report.problems.filter({ $0.kind != .lowFreeSpace }).isEmpty {
                            ProblemsView(model: model, problems: report.problems)
                        }
                        CategoryListView(model: model, report: report)
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text(model.scanStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260)
                }
                Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                    .disabled(model.isScanning)
                Button {
                    model.activeSheet = .confirm
                } label: {
                    Label("Optimize \(ByteText.format(model.selectedBytes))", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isScanning || model.selectedItems.isEmpty)
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .confirm:
                ConfirmView(model: model)
            case .progress:
                OptimizeProgressView(model: model)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("See what uses space on your Mac")
                .font(.title2)
            Text("The scan only reads. Nothing changes until you press Optimize.")
                .foregroundStyle(.secondary)
            if model.isScanning {
                ProgressView()
                Text(model.scanStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            } else {
                Button("Scan") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func banners(_ report: ScanReport) -> some View {
        if let lowSpace = report.problems.first(where: { $0.kind == .lowFreeSpace }) {
            BannerView(systemImage: "exclamationmark.triangle.fill", tint: .red, text: lowSpace.detail)
        }
        if report.hasUnreadableFolders {
            BannerView(systemImage: "lock.fill", tint: .orange, text: "Some folders could not be read. Give Full Disk Access for full numbers.") {
                Button("Open Settings") {
                    if let url = URL(string: ContentView.FULL_DISK_ACCESS_URL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
