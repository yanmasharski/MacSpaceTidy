import Foundation

/// Reads data that only Apple command line tools know.
public enum SystemTools {
    public struct SimulatorRuntime: Sendable, Equatable {
        public let identifier: String
        public let name: String
        public let sizeBytes: Int64
    }

    private struct RuntimeRecord: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let sizeBytes: Int64?
        let platformIdentifier: String?
        let deletable: Bool?
    }

    private static let XCRUN = "/usr/bin/xcrun"
    private static let TMUTIL = "/usr/bin/tmutil"
    private static let SIMCTL_TIMEOUT_SECONDS = 60.0
    private static let TMUTIL_TIMEOUT_SECONDS = 15.0
    private static let SNAPSHOT_PREFIX = "com.apple.TimeMachine."
    private static let PLATFORM_PREFIX = "com.apple.platform."
    private static let PLATFORM_SUFFIX = "simulator"
    private static let PLATFORM_NAMES = ["iphone": "iOS", "watch": "watchOS", "appletv": "tvOS", "xr": "visionOS"]

    /// Nil when `simctl` is missing, fails, or hangs past the timeout.
    public static func simulatorRuntimes() -> [SimulatorRuntime]? {
        guard let result = CommandRunner.run(XCRUN, ["simctl", "runtime", "list", "-j"], timeoutSeconds: SIMCTL_TIMEOUT_SECONDS),
              result.exitCode == 0 else {
            return nil
        }
        return parseSimulatorRuntimes(json: Data(result.output.utf8))
    }

    public static func parseSimulatorRuntimes(json: Data) -> [SimulatorRuntime]? {
        guard let records = try? JSONDecoder().decode([String: RuntimeRecord].self, from: json) else {
            return nil
        }
        return records.values
            .filter { $0.deletable ?? true }
            .map { record in
                SimulatorRuntime(
                    identifier: record.identifier,
                    name: "\(platformName(record.platformIdentifier)) \(record.version ?? "?") (\(record.build ?? "?"))",
                    sizeBytes: record.sizeBytes ?? 0
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Nil when `tmutil` fails or hangs.
    public static func localSnapshotCount() -> Int? {
        guard let result = CommandRunner.run(TMUTIL, ["listlocalsnapshots", "/"], timeoutSeconds: TMUTIL_TIMEOUT_SECONDS),
              result.exitCode == 0 else {
            return nil
        }
        return result.output.split(separator: "\n").filter { $0.hasPrefix(SNAPSHOT_PREFIX) }.count
    }

    /// `com.apple.platform.iphonesimulator` → `iOS`.
    private static func platformName(_ identifier: String?) -> String {
        guard let identifier, identifier.hasPrefix(PLATFORM_PREFIX), identifier.hasSuffix(PLATFORM_SUFFIX) else {
            return "Simulator"
        }
        let platform = String(identifier.dropFirst(PLATFORM_PREFIX.count).dropLast(PLATFORM_SUFFIX.count))
        return PLATFORM_NAMES[platform] ?? platform
    }
}
