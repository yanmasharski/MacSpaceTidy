import MacSpaceTidyCore
import SwiftUI

struct OptimizeProgressView: View {
    private static let WIDTH: CGFloat = 520
    private static let LIST_HEIGHT: CGFloat = 180

    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let result = model.result {
                resultView(result)
            } else {
                Text("Working…").font(.title2.bold())
                ProgressView(value: Double(model.optimizeIndex), total: Double(max(model.optimizeTotal, 1)))
                Text(model.optimizeStep)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancelOptimize() }
                        .help("Stops after the current item.")
                }
            }
        }
        .padding(20)
        .frame(width: OptimizeProgressView.WIDTH)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func resultView(_ result: OptimizeResult) -> some View {
        let problems = result.outcomes.filter { $0.status != .done }
        Text("Freed \(ByteText.format(max(result.freedBytes, 0)))")
            .font(.largeTitle.bold())
        Text("Measured on the disk before and after. Now \(ByteText.format(result.diskAfter.freeBytes)) free.")
            .foregroundStyle(.secondary)
        if result.wasCancelled {
            Label("Canceled. The rest was not touched.", systemImage: "stop.circle")
        }
        if model.deleteMode == .trash && result.outcomes.contains(where: { $0.status == .done && !$0.item.needsAdmin }) {
            Label("Empty the Trash to free the space of trashed items.", systemImage: "trash")
                .foregroundStyle(.secondary)
        }
        let noDisk = result.outcomes.filter { $0.status == .skipped(Optimizer.NO_DISK_REASON) }
        if !noDisk.isEmpty {
            Label(
                "\(noDisk.count) moves skipped (\(ByteText.format(noDisk.reduce(0) { $0 + $1.item.size.bytes }))): no external disk. "
                    + "Choose one in Settings (Cmd-,), then optimize again.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
        let keptCopies = result.outcomes.filter { $0.status == .done && $0.item.action == .moveBack }.compactMap(\.item.linkTarget)
        ForEach(keptCopies, id: \.self) { target in
            Label("The copy on the external disk stays at \(target). Delete it when you are sure.", systemImage: "externaldrive")
                .foregroundStyle(.secondary)
        }
        if model.report?.problems.contains(where: { $0.kind == .timeMachineSnapshots }) == true {
            Label("Time Machine snapshots can hold the freed space for a while.", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        }
        if !problems.isEmpty {
            Text("Not done: \(problems.count)").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, outcome in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(outcome.item.title).lineLimit(1).truncationMode(.middle)
                            Text(text(outcome.status)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: OptimizeProgressView.LIST_HEIGHT)
        }
        HStack {
            Spacer()
            Button("Done") { model.closeResult() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func text(_ status: ItemOutcome.Status) -> String {
        switch status {
        case .done: return "Done"
        case .skipped(let reason): return "Skipped: \(reason)"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}
