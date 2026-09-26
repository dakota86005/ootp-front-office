import Foundation
import OpenAPIRuntime
import PennantAPI

/// What the event stream told the app.
public enum EventSignal: Sendable, Equatable {
    /// The stream opened (a `hello` follows).
    case connected
    /// An event this build knows, decoded.
    case event(Components.Schemas.ServerEvent)
    /// An event whose type this build knows but whose payload did not decode: report it and re-read
    /// `/api/status` (SWIFTUI_REBUILD.md section 4.3). Never ignored.
    case malformed(type: String)
    /// The stream ended or failed; the client reconnects after a pause.
    case disconnected
}

/// Listens to `GET /api/v2/events` (server-sent events) and reconnects when the stream drops while the server is
/// up. An event is a nudge to re-read, never a second source of truth: every connection opens with a `hello`
/// carrying the status, so a gap is closed by the next connection.
///
/// Known events are passed on; an event type this build has never heard of is ignored (a newer server may send
/// it); a known type that did not decode is passed on as `malformed`.
public struct EventClient: Sendable {
    public let client: Client
    public var reconnectDelay: Duration
    /// Called for an unknown event type (for the log only).
    public var onUnknown: @Sendable (String) -> Void

    public init(client: Client, reconnectDelay: Duration = .seconds(1), onUnknown: @escaping @Sendable (String) -> Void = { _ in }) {
        self.client = client
        self.reconnectDelay = reconnectDelay
        self.onUnknown = onUnknown
    }

    /// Reads one connection to its end, passing each event on. Throws what the connection threw.
    public func readOnce(_ handle: (EventSignal) async -> Void) async throws {
        let response = try await client.streamEvents()
        let events = try response.ok.body.textEventStream
            .asDecodedServerSentEventsWithJSONData(of: Components.Schemas.ServerEvent.self)
        await handle(.connected)
        for try await message in events {
            guard let event = message.data else { continue }
            switch event.reading {
            case .known:
                await handle(.event(event))
            case .unknown(let type):
                onUnknown(type)
            case .malformed(let type):
                await handle(.malformed(type: type))
            }
        }
    }

    /// Connects, reads, and connects again after `reconnectDelay` whenever the stream ends, until the task is
    /// cancelled (the app cancels it when the server stops).
    public func run(_ handle: (EventSignal) async -> Void) async {
        while !Task.isCancelled {
            do {
                try await readOnce(handle)
            } catch {
                if Task.isCancelled { return }
            }
            if Task.isCancelled { return }
            await handle(.disconnected)
            try? await Task.sleep(for: reconnectDelay)
        }
    }
}
