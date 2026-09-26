import Foundation

/// The server's log file (SWIFTUI_REBUILD.md section 5.3, step 4): every line the sidecar writes, and the
/// controller's own notes, in `~/Library/Logs/Pennant/server.log` (a development run passes its own folder).
///
/// When the file passes `maxBytes` it becomes `server.1.log` (the older ones shift to `.2`, `.3`), and at most
/// `keep` old files are kept. Tokens and keys are never written: they travel on stdin, which is not logged.
public final class ServerLog: @unchecked Sendable {
    public let url: URL
    public let maxBytes: Int
    public let keep: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private var size = 0

    public init(folder: URL, name: String = "server.log", maxBytes: Int = 5_000_000, keep: Int = 3) {
        url = folder.appending(path: name)
        self.maxBytes = maxBytes
        self.keep = keep
    }

    deinit {
        try? handle?.close()
    }

    /// The rotated file number `n` (1 is the newest): `server.1.log`.
    public func rotated(_ n: Int) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appending(path: "\(base).\(n).\(url.pathExtension)")
    }

    /// Appends one line, with the time it was written.
    public func write(_ line: String, source: String = "server") {
        let stamp = Date.now.formatted(.iso8601)
        let data = Data("\(stamp) [\(source)] \(line)\n".utf8)
        lock.withLock {
            openIfNeeded()
            if size + data.count > maxBytes, size > 0 {
                rotate()
                openIfNeeded()
            }
            guard let handle else { return }
            do {
                try handle.write(contentsOf: data)
                size += data.count
            } catch {
                // A log that cannot be written must never stop the server
            }
        }
    }

    private func openIfNeeded() {
        guard handle == nil else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let manager = FileManager.default
        try? manager.removeItem(at: rotated(keep))
        if keep > 1 {
            for n in stride(from: keep - 1, through: 1, by: -1) where manager.fileExists(atPath: rotated(n).path) {
                try? manager.moveItem(at: rotated(n), to: rotated(n + 1))
            }
        }
        if keep > 0 {
            try? manager.moveItem(at: url, to: rotated(1))
        } else {
            try? manager.removeItem(at: url)
        }
        size = 0
    }
}
