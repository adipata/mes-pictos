import Foundation
import os

/// Diagnostic journal for the speech and audio path.
///
/// Each line goes to the unified log (Console.app on a Mac, subsystem `lu.pata.mespictos`,
/// category `audio`) and to a small text file in Caches. The file survives a restart of the app,
/// so after the voice stopped the parent can share what happened just before, from Settings.
/// The file is trimmed to its newer half once it passes `maxBytes`.
nonisolated enum AudioLog {
    private static let logger = Logger(subsystem: "lu.pata.mespictos", category: "audio")
    private static let queue = DispatchQueue(label: "mespictos.audio-log", qos: .utility)
    private static let maxBytes = 1_000_000
    private static let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    static let fileURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journal-audio.txt")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(stamp.format(Date())) \(message)\n"
        queue.async { append(line) }
    }

    /// Empties the journal.
    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            append("\(stamp.format(Date())) journal cleared\n")
        }
    }

    private static func append(_ line: String) {
        let fileManager = FileManager.default
        if let size = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
           size > maxBytes,
           let old = try? Data(contentsOf: fileURL) {
            var tail = old.suffix(maxBytes / 2)
            if let newline = tail.firstIndex(of: 0x0A) {
                tail = tail[tail.index(after: newline)...]
            }
            try? Data(tail).write(to: fileURL, options: .atomic)
        }
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
