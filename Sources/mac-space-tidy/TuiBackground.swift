import Foundation
import MacSpaceTidyCore

/// State written by background work (scan, optimize) and read by the main loop on each frame.
final class TuiBackground: @unchecked Sendable {
    struct Snapshot {
        var report: ScanReport?
        /// Changes when a new main scan arrives, so the main loop resets the selection.
        var scanVersion = 0
        var isScanning = false
        var isScanningExternal = false
        var scanStep = ""
        var isOptimizing = false
        var optimizeIndex = 0
        var optimizeStep = ""
        var result: OptimizeResult?
        var errorText: String?
        var isCancelRequested = false
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func read() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func modify(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&snapshot)
        lock.unlock()
    }
}
