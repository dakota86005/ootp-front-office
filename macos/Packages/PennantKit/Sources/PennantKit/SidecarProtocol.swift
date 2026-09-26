import Foundation
import Security

/// The app's side of the conversation with the sidecar (`server/sidecar.ts`; SWIFTUI_REBUILD.md section 5.1, "As
/// built"): the handshake line written to its stdin, the ready and failure lines read from its stdout, and what its
/// exit codes mean.
public enum SidecarProtocol {
    public static let readyPrefix = "PENNANT_READY "
    public static let failedPrefix = "PENNANT_FAILED "
    /// The server refuses a shorter token (`MIN_TOKEN_LENGTH` in `server/apiToken.ts`).
    public static let minimumTokenLength = 32

    /// A fresh token for one launch: 32 random bytes as 64 lowercase hex characters.
    public static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "the system random source failed (\(status))")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private struct Handshake: Encodable {
        let token: String
        let keys: [String: String]
    }

    private struct KeysUpdate: Encodable {
        let keys: [String: String]
    }

    private static func line(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    /// The first stdin line: `{"keys":{…},"token":"…"}` and a newline. The keys are the Keychain's, by provider id.
    public static func handshakeLine(token: String, keys: [String: String]) throws -> Data {
        try line(Handshake(token: token, keys: keys))
    }

    /// A later stdin line that replaces the keys without a restart (the GM changed one in Settings, N13).
    public static func keysLine(keys: [String: String]) throws -> Data {
        try line(KeysUpdate(keys: keys))
    }

    /// What one stdout line says.
    public static func parse(line: String) -> SidecarLine {
        let decoder = JSONDecoder()
        if line.hasPrefix(readyPrefix),
           let ready = try? decoder.decode(SidecarReady.self, from: Data(line.dropFirst(readyPrefix.count).utf8)) {
            return .ready(ready)
        }
        if line.hasPrefix(failedPrefix),
           let failure = try? decoder.decode(SidecarFailure.self, from: Data(line.dropFirst(failedPrefix.count).utf8)) {
            return .failed(failure)
        }
        return .log(line)
    }
}

/// One line of the sidecar's stdout.
public enum SidecarLine: Sendable, Equatable {
    /// `PENNANT_READY {"port":N,"pid":N,"version":"…"}`: listening on 127.0.0.1 at that port.
    case ready(SidecarReady)
    /// `PENNANT_FAILED {"reason":"…","message":"…"}`: it could not start and is about to exit.
    case failed(SidecarFailure)
    /// Anything else: the server's ordinary log.
    case log(String)
}

public struct SidecarReady: Codable, Sendable, Equatable {
    public var port: Int
    public var pid: Int32?
    public var version: String?

    public init(port: Int, pid: Int32? = nil, version: String? = nil) {
        self.port = port
        self.pid = pid
        self.version = version
    }
}

/// The server's own account of why it could not start. `message` is the server's sentence and is shown as it is.
public struct SidecarFailure: Codable, Sendable, Equatable {
    public var reason: String
    public var message: String

    public init(reason: String, message: String) {
        self.reason = reason
        self.message = message
    }

    /// `reason: "locked"`: another copy of Pennant holds the data folder (exit code 3).
    public var isLocked: Bool { reason == "locked" }
}

/// How the sidecar ended, read from its exit (0 stopped cleanly, 1 could not start, 2 no usable handshake, 3 the
/// data folder is in use).
public enum SidecarExit: Sendable, Equatable {
    case stoppedCleanly
    case couldNotStart
    case noHandshake
    case locked
    case exited(Int32)
    case killed(signal: Int32)

    public init(_ exit: ProcessExit) {
        if exit.bySignal {
            self = .killed(signal: exit.status)
            return
        }
        switch exit.status {
        case 0: self = .stoppedCleanly
        case 1: self = .couldNotStart
        case 2: self = .noHandshake
        case 3: self = .locked
        default: self = .exited(exit.status)
        }
    }
}

/// A child process's end: its exit status, or the signal that ended it.
public struct ProcessExit: Sendable, Equatable {
    public var status: Int32
    public var bySignal: Bool

    public init(status: Int32, bySignal: Bool = false) {
        self.status = status
        self.bySignal = bySignal
    }
}
