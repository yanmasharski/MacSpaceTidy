import Foundation

public enum ProcessCheck {
    private static let PGREP = "/usr/bin/pgrep"
    private static let TIMEOUT_SECONDS = 5.0

    /// True when a process with exactly this name runs. Finds command line tools too, not only apps.
    public static func isRunning(_ processName: String) -> Bool {
        return CommandRunner.run(PGREP, ["-x", processName], timeoutSeconds: TIMEOUT_SECONDS)?.exitCode == 0
    }
}
