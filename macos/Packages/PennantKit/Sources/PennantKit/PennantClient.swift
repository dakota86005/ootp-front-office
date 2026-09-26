import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import PennantAPI

/// The generated client, pointed at the running server with the launch's token (SWIFTUI_REBUILD.md section 4.3).
public enum PennantClient {
    /// `http://127.0.0.1:<port>`: the sidecar binds only the loopback address.
    public static func baseURL(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    /// A client for one launch. The transport is URLSession's unless a test passes its own.
    public static func make(port: Int, token: String, transport: (any ClientTransport)? = nil) -> Client {
        Client(
            serverURL: baseURL(port: port),
            transport: transport ?? URLSessionTransport(configuration: .init(session: session)),
            middlewares: [BearerTokenMiddleware(token: token)]
        )
    }

    /// One session for every client: no cookies or cache (every answer is live), and a request that goes quiet
    /// for a minute fails. The event stream sends a comment every 15 seconds, so it is never idle that long.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24 * 7
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()
}
