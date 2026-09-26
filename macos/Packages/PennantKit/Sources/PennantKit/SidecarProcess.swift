import Foundation

/// What starting the server needs: the Node binary, its arguments, the environment and where it runs.
public struct LaunchSpec: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectory: URL?

    public init(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
    }
}

/// Starts a child process. The app uses `FoundationSidecarLauncher`; tests pass a scripted one.
public protocol SidecarLauncher: Sendable {
    func launch(_ spec: LaunchSpec) throws -> any SidecarProcess
}

/// A running child: its output as lines, its stdin, its end, and the two ways to stop it.
public protocol SidecarProcess: AnyObject, Sendable {
    var pid: Int32 { get }
    /// stdout, line by line; finishes when the pipe closes.
    var outputLines: AsyncStream<String> { get }
    /// stderr, line by line; finishes when the pipe closes.
    var errorLines: AsyncStream<String> { get }
    /// Writes to stdin (the stdin pipe stays open for as long as the process runs).
    func send(_ data: Data) throws
    /// Waits for the process to end; nil if the waiting task was cancelled first.
    func waitForExit() async -> ProcessExit?
    /// SIGTERM: the sidecar stops cleanly.
    func terminate()
    /// SIGKILL.
    func kill()
}

/// Starts processes with Foundation's `Process`, with pipes for stdin, stdout and stderr.
public struct FoundationSidecarLauncher: SidecarLauncher {
    public init() {}

    public func launch(_ spec: LaunchSpec) throws -> any SidecarProcess {
        try FoundationSidecarProcess(spec)
    }
}

final class FoundationSidecarProcess: SidecarProcess, @unchecked Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let exitState = ExitState()
    let outputLines: AsyncStream<String>
    let errorLines: AsyncStream<String>

    init(_ spec: LaunchSpec) throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = spec.environment
        if let directory = spec.currentDirectory { process.currentDirectoryURL = directory }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        outputLines = Self.lines(of: stdout.fileHandleForReading)
        errorLines = Self.lines(of: stderr.fileHandleForReading)
        let exitState = exitState
        process.terminationHandler = { process in
            exitState.finish(ProcessExit(
                status: process.terminationStatus,
                bySignal: process.terminationReason == .uncaughtSignal
            ))
        }
        try process.run()
        // The child holds its own copies of the pipe ends; closing ours lets EOF arrive when it exits
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        try? stdin.fileHandleForReading.close()
    }

    var pid: Int32 { process.processIdentifier }

    func send(_ data: Data) throws {
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    func waitForExit() async -> ProcessExit? {
        await exitState.wait()
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func kill() {
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    /// The pipe's output, line by line. Read with a readability handler, which hands over whatever arrived: a
    /// line is passed on as soon as its newline does, never held back to fill a buffer.
    private static func lines(of handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let splitter = LineSplitter()
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let rest = splitter.finish() { continuation.yield(rest) }
                    continuation.finish()
                    return
                }
                for line in splitter.append(data) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

/// Splits bytes into lines (LF, with a CR before it dropped), keeping a partial line until its end arrives.
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                var line = pending[pending.startIndex..<newline]
                if line.last == 0x0D { line = line.dropLast() }
                lines.append(String(decoding: line, as: UTF8.self))
                pending = Data(pending[pending.index(after: newline)...])
            }
            return lines
        }
    }

    /// What is left when the pipe closes, if anything.
    func finish() -> String? {
        lock.withLock {
            defer { pending = Data() }
            return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
        }
    }
}

/// A one-time result that any number of tasks can wait for, each cancellable on its own.
final class ExitState: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProcessExit?
    private var waiters: [UUID: CheckedContinuation<ProcessExit?, Never>] = [:]

    func finish(_ exit: ProcessExit) {
        let waiting: [CheckedContinuation<ProcessExit?, Never>] = lock.withLock {
            guard result == nil else { return [] }
            result = exit
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        for waiter in waiting { waiter.resume(returning: exit) }
    }

    var finished: ProcessExit? { lock.withLock { result } }

    func wait() async -> ProcessExit? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready: ProcessExit?? = lock.withLock {
                    if let result { return .some(result) }
                    if Task.isCancelled { return .some(nil) }
                    waiters[id] = continuation
                    return .none
                }
                if case .some(let value) = ready { continuation.resume(returning: value) }
            }
        } onCancel: {
            let waiter = lock.withLock { waiters.removeValue(forKey: id) }
            waiter?.resume(returning: nil)
        }
    }
}
