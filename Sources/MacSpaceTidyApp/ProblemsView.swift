import MacSpaceTidyCore
import SwiftUI

struct ProblemsView: View {
    let model: AppModel
    let problems: [Problem]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    if problem.kind != .lowFreeSpace {
                        row(problem)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Problems", systemImage: "exclamationmark.triangle")
                .font(.headline)
        }
    }

    private func row(_ problem: Problem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(problem.kind))
                .foregroundStyle(.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                if let path = problem.path {
                    Text(PathTools.abbreviate(path, home: NSHomeDirectory()))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(problem.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            fixButton(problem)
        }
    }

    @ViewBuilder
    private func fixButton(_ problem: Problem) -> some View {
        switch problem.kind {
        case .strayNestedLink, .brokenLink:
            if let path = problem.path {
                Button("Remove link") { model.removeLink(path) }
                    .help("Removes only the link. The data it points to stays.")
            }
        case .timeMachineSnapshots:
            Button("Delete snapshots") { model.deleteSnapshots() }
                .help("Needs your admin password.")
        case .diskNotMounted:
            Text("Connect the disk")
                .foregroundStyle(.secondary)
        case .lowFreeSpace:
            EmptyView()
        }
    }

    private func icon(_ kind: ProblemKind) -> String {
        switch kind {
        case .diskNotMounted: return "externaldrive.badge.xmark"
        case .strayNestedLink: return "link.badge.plus"
        case .brokenLink: return "link"
        case .timeMachineSnapshots: return "clock.arrow.circlepath"
        case .lowFreeSpace: return "exclamationmark.triangle"
        }
    }
}
