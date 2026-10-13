import AppKit

// Snapshot mode renders the window to a PNG and exits; otherwise the normal app starts.
if let job = MainActor.assumeIsolated({ SnapshotJob(arguments: CommandLine.arguments) }) {
    exit(MainActor.assumeIsolated { job.run() })
}
MacSpaceTidyApp.main()
