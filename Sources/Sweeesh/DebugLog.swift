import Foundation
import OSLog

enum DebugLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Sweeesh"

    struct Channel {
        let name: String
        let logger: Logger
    }

    static let app = Channel(name: "app", logger: Logger(subsystem: subsystem, category: "app"))
    static let settings = Channel(name: "settings", logger: Logger(subsystem: subsystem, category: "settings"))
    static let hotkeys = Channel(name: "hotkeys", logger: Logger(subsystem: subsystem, category: "hotkeys"))
    static let dock = Channel(name: "dock", logger: Logger(subsystem: subsystem, category: "dock"))
    static let windows = Channel(name: "windows", logger: Logger(subsystem: subsystem, category: "windows"))
    static let accessibility = Channel(name: "accessibility", logger: Logger(subsystem: subsystem, category: "accessibility"))

    #if DEBUG
    private static let fileSink = DebugLogFileSink()

    static func debug(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.debug("\(rendered, privacy: .public)")
        writeToFile(level: "DEBUG", channel: channel, message: rendered)
    }

    static func info(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.info("\(rendered, privacy: .public)")
        writeToFile(level: "INFO", channel: channel, message: rendered)
    }

    static func error(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.error("\(rendered, privacy: .public)")
        writeToFile(level: "ERROR", channel: channel, message: rendered)
    }

    static var logFilePathDescription: String {
        fileSink.logFileURL.path
    }

    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["SWEEESH_DEBUG_LOGS"] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: "settings.debugLoggingEnabled")
    }

    private static func writeToFile(level: String, channel: Channel, message: String) {
        let line = "\(timestamp()) [\(level)] [\(channel.name)] \(message)\n"
        Task {
            await fileSink.append(line: line)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
    #else
    static func debug(_ channel: Channel, _ message: @autoclosure () -> String) {}
    static func info(_ channel: Channel, _ message: @autoclosure () -> String) {}
    static func error(_ channel: Channel, _ message: @autoclosure () -> String) {}
    static var logFilePathDescription: String { "" }
    #endif
}

#if DEBUG
private actor DebugLogFileSink {
    let logFileURL: URL

    init() {
        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Sweeesh", isDirectory: true)
        self.logFileURL = logsDirectory.appendingPathComponent("debug.log")
    }

    func append(line: String) {
        do {
            let directoryURL = logFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: logFileURL.path) == false {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }

            let data = Data(line.utf8)
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Sweeesh debug log file write failed: %@", error.localizedDescription)
        }
    }
}
#endif
