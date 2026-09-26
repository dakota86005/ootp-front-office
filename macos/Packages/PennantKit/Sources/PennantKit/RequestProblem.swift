import Foundation
import OpenAPIRuntime

/// Why a request to the server did not do what was asked, in the few kinds a window can say plainly (review S9).
/// The server's own sentence is kept as it came; anything else is a kind with a structural title in the String
/// Catalog, and the raw error goes to the log (`detail`), never onto the screen as text.
public enum RequestProblem: Error, Hashable, Sendable {
    /// The server refused and said why (an `ApiError`'s `error`, a failed import's `lastError`).
    case served(String)
    /// The server is not running, so nothing could be asked.
    case notRunning
    /// The server could not be reached (the connection failed or timed out).
    case unreachable(detail: String)
    /// The server answered something this build did not expect, or the answer did not decode.
    case failed(detail: String)

    /// The raw error, for the log and a help tag; nil for a served sentence or a server that is not running.
    public var detail: String? {
        switch self {
        case .served, .notRunning: nil
        case .unreachable(let detail), .failed(let detail): detail
        }
    }

    /// The kind of problem a thrown error is.
    public static func from(_ error: any Error) -> RequestProblem {
        if let problem = error as? RequestProblem { return problem }
        let cause = (error as? ClientError)?.underlyingError ?? error
        if cause is URLError || (cause as NSError).domain == NSURLErrorDomain {
            return .unreachable(detail: String(describing: error))
        }
        return .failed(detail: String(describing: error))
    }

    /// An answer with a status code the contract does not document.
    public static func undocumented(_ code: Int, operation: String) -> RequestProblem {
        .failed(detail: "\(operation): undocumented HTTP \(code)")
    }

    /// An answer with a status code the contract does not document, read for the server's sentence: a route that fails
    /// answers `{ "error": sentence }` (a `/v2` route adds the raw `detail`), so the window can say what the server said.
    public static func undocumented(_ code: Int, body: HTTPBody?, operation: String) async -> RequestProblem {
        if let body, let data = try? await Data(collecting: body, upTo: 64 * 1024),
           let answer = try? JSONDecoder().decode(ServedError.self, from: data), !answer.error.isEmpty {
            return .served(answer.error)
        }
        return undocumented(code, operation: operation)
    }

    private struct ServedError: Decodable {
        let error: String
    }
}
