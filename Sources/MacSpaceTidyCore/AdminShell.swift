import Foundation

/// Runs shell commands as root through the standard macOS password prompt.
public enum AdminShell {
    private static let OSASCRIPT = "/usr/bin/osascript"
    /// The user needs time to type the password.
    private static let TIMEOUT_SECONDS = 600.0

    /// Returns nil on success, else a short error text.
    public static func run(_ commands: [String]) -> String? {
        let script = "do shell script \"\(appleScriptEscaped(commands.joined(separator: "; ")))\" with administrator privileges"
        guard let result = CommandRunner.run(OSASCRIPT, ["-e", script], timeoutSeconds: TIMEOUT_SECONDS) else {
            return "The admin command did not finish."
        }
        return result.exitCode == 0 ? nil : "The admin command failed or was canceled."
    }

    public static func shellQuoted(_ text: String) -> String {
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        return text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
