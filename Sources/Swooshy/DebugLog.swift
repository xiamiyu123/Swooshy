import Foundation
import OSLog

enum DebugLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Swooshy"

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
        if ProcessInfo.processInfo.environment["SWOOSHY_DEBUG_LOGS"] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: "settings.debugLoggingEnabled")
    }

    private static func writeToFile(level: String, channel: Channel, message: String) {
        Task {
            await fileSink.append(level: level, channel: channel.name, message: message)
        }
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
    private let timestampFormatter = ISO8601DateFormatter()
    private var fileHandle: FileHandle?

    init() {
        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Swooshy", isDirectory: true)
        self.logFileURL = logsDirectory.appendingPathComponent("debug.log")
    }

    deinit {
        do {
            try fileHandle?.close()
        } catch {
            NSLog("Swooshy debug log file close failed: %@", error.localizedDescription)
        }
    }

    func append(level: String, channel: String, message: String) {
        do {
            let line = "\(timestampFormatter.string(from: Date())) [\(level)] [\(channel)] \(message)\n"
            let handle = try logFileHandle()
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            NSLog("Swooshy debug log file write failed: %@", error.localizedDescription)
        }
    }

    private func logFileHandle() throws -> FileHandle {
        if let fileHandle {
            return fileHandle
        }

        let directoryURL = logFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: logFileURL.path) == false {
            let created = FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            guard created else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSFilePathErrorKey: logFileURL.path]
                )
            }
        }

        let handle = try FileHandle(forWritingTo: logFileURL)
        self.fileHandle = handle
        return handle
    }
}
#endif
