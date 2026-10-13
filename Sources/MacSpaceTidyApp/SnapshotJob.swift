import AppKit
import MacSpaceTidyCore
import SwiftUI

/// `MacSpaceTidyApp --snapshot out.png --demo [--dark] [--sheet confirm] [--width 880]`
/// Draws the window with made-up data and writes a PNG, so README screenshots need no screen and no real data.
@MainActor
struct SnapshotJob {
    private static let DEFAULT_WIDTH: CGFloat = 880
    private static let SCALE: CGFloat = 2
    private static let SETTLE_SECONDS = 0.4

    let outputPath: String
    let isDark: Bool
    let sheet: String?
    let width: CGFloat

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
            return nil
        }
        outputPath = arguments[index + 1]
        isDark = arguments.contains("--dark")
        sheet = arguments.firstIndex(of: "--sheet").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        width = arguments.firstIndex(of: "--width").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
            .map { CGFloat($0) } ?? SnapshotJob.DEFAULT_WIDTH
    }

    func run() -> Int32 {
        // README screenshots are in English, whatever the language of this Mac is.
        UserDefaults.standard.set("en_US", forKey: "AppleLocale")
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let model = AppModel()
        DemoData.configure(model)
        guard let report = model.report else {
            return 1
        }
        let background = Color(nsColor: .windowBackgroundColor)
        let view: AnyView
        if sheet == "confirm" {
            model.plan.selected.formUnion(report.items.filter { $0.action == .move }.map(\.id))
            view = AnyView(ConfirmView(model: model).background(background))
        } else {
            view = AnyView(
                VStack(spacing: 0) {
                    header(model)
                    Divider()
                    ReportView(model: model, report: report, scrolls: false)
                }
                .background(background)
            )
        }
        return write(view) ? 0 : 1
    }

    /// The window toolbar is not part of the content view, so the snapshot draws a similar one.
    private func header(_ model: AppModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive").foregroundStyle(.secondary)
            Text("MacSpaceTidy").font(.headline)
            Spacer()
            Button("Scan", systemImage: "magnifyingglass") {}
            Button {} label: {
                Label("Optimize \(ByteText.format(model.selectedBytes))", systemImage: "sparkles").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func write(_ view: AnyView) -> Bool {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: ceil(host.fittingSize.height))
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its layout passes before drawing.
        RunLoop.current.run(until: Date().addingTimeInterval(SnapshotJob.SETTLE_SECONDS))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * SnapshotJob.SCALE), pixelsHigh: Int(size.height * SnapshotJob.SCALE),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return false
        }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            print("Wrote \(outputPath) (\(Int(size.width))x\(Int(size.height)) points)")
            return true
        } catch {
            print("Could not write \(outputPath): \(error)")
            return false
        }
    }
}
