import Foundation
import Testing
@testable import Swooshy

struct DebugLogTests {
    @Test
    func rotatesOversizedCurrentLogBeforeWriting() async throws {
        let directory = try makeTemporaryLogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentLogURL = directory.appendingPathComponent("debug.log")
        try write(String(repeating: "x", count: 5 * 1024 * 1024 + 1), to: currentLogURL)

        let sink = DebugLogFileSink(logDirectoryURL: directory)
        await sink.append(level: "INFO", channel: "tests", message: "hello")

        let currentLogContents = try String(contentsOf: currentLogURL, encoding: .utf8)
        #expect(currentLogContents.contains("hello"))

        let archives = archivedLogURLs(in: directory)
        #expect(archives.count == 1)

        let archiveSize = try fileSize(for: archives[0])
        #expect(archiveSize > 5 * 1024 * 1024)
    }

    @Test
    func prunesExpiredArchivesAndKeepsOnlyRecentHistory() async throws {
        let directory = try makeTemporaryLogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentLogURL = directory.appendingPathComponent("debug.log")
        try write("seed", to: currentLogURL)

        let now = Date()
        for index in 0..<12 {
            let archiveURL = directory.appendingPathComponent("debug-archive-\(index).log")
            try write("archive-\(index)", to: archiveURL)
            try setModificationDate(now.addingTimeInterval(TimeInterval(-(index + 1) * 60 * 60)), for: archiveURL)
        }

        let expiredArchiveURL = directory.appendingPathComponent("debug-expired.log")
        try write("expired", to: expiredArchiveURL)
        try setModificationDate(now.addingTimeInterval(-(8 * 24 * 60 * 60)), for: expiredArchiveURL)

        let sink = DebugLogFileSink(logDirectoryURL: directory)
        await sink.append(level: "INFO", channel: "tests", message: "cleanup")

        let archives = archivedLogURLs(in: directory)
        #expect(archives.count == 10)
        #expect(!archives.contains(expiredArchiveURL))

        let remainingDates = try archives.map { try modificationDate(for: $0) }.compactMap { $0 }
        let oldestRemaining = try #require(remainingDates.min())
        #expect(oldestRemaining >= now.addingTimeInterval(-(12 * 60 * 60)))
    }

    @Test
    func fileWriterPreservesAppendOrder() async throws {
        let directory = try makeTemporaryLogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentLogURL = directory.appendingPathComponent("debug.log")
        let writer = DebugLogFileWriter(fileSink: DebugLogFileSink(logDirectoryURL: directory))

        for index in 0..<100 {
            writer.append(level: "INFO", channel: "tests", message: "message-\(index)")
        }
        await writer.flush()

        let contents = try String(contentsOf: currentLogURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")

        #expect(lines.count == 100)
        #expect(
            lines.enumerated().allSatisfy { index, line in
                line.hasSuffix("message-\(index)")
            }
        )
    }

    @Test
    func reopensCurrentLogAfterExternalRotation() async throws {
        let directory = try makeTemporaryLogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentLogURL = directory.appendingPathComponent("debug.log")
        let sink = DebugLogFileSink(logDirectoryURL: directory)
        await sink.append(level: "INFO", channel: "tests", message: "before-rotation")

        // Simulate another running instance rotating the log from under us.
        let externalArchiveURL = directory.appendingPathComponent("debug-external.log")
        try FileManager.default.moveItem(at: currentLogURL, to: externalArchiveURL)

        await sink.append(level: "INFO", channel: "tests", message: "after-rotation")

        let currentLogContents = try String(contentsOf: currentLogURL, encoding: .utf8)
        #expect(currentLogContents.contains("after-rotation"))

        let archiveContents = try String(contentsOf: externalArchiveURL, encoding: .utf8)
        #expect(archiveContents.contains("before-rotation"))
        #expect(!archiveContents.contains("after-rotation"))
    }

    @Test
    func reopensCurrentLogAfterExternalReplacement() async throws {
        let directory = try makeTemporaryLogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentLogURL = directory.appendingPathComponent("debug.log")
        let sink = DebugLogFileSink(logDirectoryURL: directory)
        await sink.append(level: "INFO", channel: "tests", message: "before-replacement")

        // Simulate another instance rotating debug.log and starting a new one.
        let externalArchiveURL = directory.appendingPathComponent("debug-external.log")
        try FileManager.default.moveItem(at: currentLogURL, to: externalArchiveURL)
        try write("replacement-seed\n", to: currentLogURL)

        await sink.append(level: "INFO", channel: "tests", message: "after-replacement")

        let currentLogContents = try String(contentsOf: currentLogURL, encoding: .utf8)
        #expect(currentLogContents.contains("replacement-seed"))
        #expect(currentLogContents.contains("after-replacement"))

        let archiveContents = try String(contentsOf: externalArchiveURL, encoding: .utf8)
        #expect(!archiveContents.contains("after-replacement"))
    }
}

private func makeTemporaryLogDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Swooshy.DebugLogTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func write(_ string: String, to url: URL) throws {
    try string.data(using: .utf8)!.write(to: url)
}

private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func archivedLogURLs(in directory: URL) -> [URL] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) else {
        return []
    }

    return contents.filter { url in
        url.lastPathComponent.hasPrefix("debug-") && url.pathExtension == "log"
    }
}

private func modificationDate(for url: URL) throws -> Date? {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    return values.contentModificationDate
}

private func fileSize(for url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values.fileSize ?? 0)
}
