import Foundation

public enum CommandRunner {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let output: String
    }

    /// Runs a command and returns nil on timeout or launch failure.
    /// Some system tools hang (`xcrun simctl runtime list` took over 2 minutes once).
    public static func run(_ executable: String, _ arguments: [String], timeoutSeconds: Double) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read on another thread so a full pipe buffer cannot block the child.
        let outputBox = OutputBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            outputBox.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            return nil
        }
        readDone.wait()
        return Result(exitCode: process.terminationStatus, output: String(decoding: outputBox.data, as: UTF8.self))
    }
}

private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
