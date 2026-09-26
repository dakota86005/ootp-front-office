import Foundation
import Observation
import OpenAPIRuntime
import PennantAPI

/// The app's shared state (SWIFTUI_REBUILD.md section 6): the server's state, its status, the current club, how
/// current the data is, and the import under way. Every fact here is the server's, read through the generated
/// client or pushed on the event stream; the model decides nothing about baseball.
///
/// Stores reload with `.task(id: model.importStamp)`, which changes only when a new import lands.
@Observable @MainActor
public final class AppModel {
    public let configuration: ServerConfiguration
    public let backups: BackupManager

    /// Where the server is in its life.
    public private(set) var serverState: ServerState = .idle
    /// The latest `/api/status`, kept current by the event stream.
    public private(set) var status: Components.Schemas.ServerStatus?
    /// `/api/settings`: the preferences, the key state and the data folder the server uses.
    public private(set) var settings: Components.Schemas.SettingsResponse?
    /// `/api/orgs`: the major-league clubs.
    public private(set) var orgs: [Components.Schemas.Org] = []
    /// The club the app is about, as the server resolved it (configured, else human-managed).
    public private(set) var club: CurrentClub?
    /// `/api/data-status`: how current the save, the export and the log are.
    public private(set) var dataStatus: Components.Schemas.DataStatus?
    /// The last import's finish time as the server reported it; changes only when a new import lands.
    public private(set) var importStamp = ""
    /// Counts successful backup restores; part of `storeKey`, so stores reload after one.
    public private(set) var restoreCount = 0
    /// Whether the event stream is connected.
    public private(set) var eventStreamConnected = false
    /// Events of a known type that did not decode, reported for the log (each also re-read `/api/status`).
    public private(set) var eventProblems: [EventProblem] = []
    /// What the first-run backup did on the latest launch (the controller takes it before every launch; a failure
    /// is the server state `.failed(.backupFailed)`).
    public private(set) var backupOutcome: BackupManager.Outcome?
    /// The last request that failed, for the log.
    public private(set) var lastRequestError: String?
    /// The client for the running server; nil while it is not ready.
    public private(set) var client: Client?

    public struct EventProblem: Sendable, Equatable {
        public var type: String
        public var at: Date
    }

    private let controller: ServerController
    private let makeClient: @Sendable (ServerConnection) -> Client
    private var stateTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var started = false
    private var shuttingDown = false

    public init(
        configuration: ServerConfiguration,
        controller: ServerController? = nil,
        makeClient: @escaping @Sendable (ServerConnection) -> Client = { PennantClient.make(port: $0.port, token: $0.token) }
    ) {
        self.configuration = configuration
        let controller = controller ?? ServerController(configuration: configuration)
        self.controller = controller
        self.backups = controller.backups
        self.makeClient = makeClient
    }

    #if DEBUG
    /// A model holding served payloads without a server, for `#Preview`s (fed by `contract/fixtures/`).
    public static func preview(
        configuration: ServerConfiguration,
        state: ServerState,
        status: Components.Schemas.ServerStatus? = nil,
        settings: Components.Schemas.SettingsResponse? = nil,
        orgs: [Components.Schemas.Org] = []
    ) -> AppModel {
        let model = AppModel(configuration: configuration)
        model.serverState = state
        model.status = status ?? state.connection?.status
        model.settings = settings
        model.orgs = orgs
        model.club = CurrentClub.from(served: settings?.organization, orgs: orgs)
        return model
    }
    #endif

    // MARK: Derived from the served status

    public var isImporting: Bool { status?.importing ?? false }
    public var importProgress: Components.Schemas.ImportProgress? { status?.importProgress }
    public var lastImport: Components.Schemas.ImportResult? { status?.lastImport }
    /// The server's own sentence about the last failed import.
    public var lastImportError: String? { status?.lastError }
    /// When OOTP wrote the export that is imported (as served).
    public var exportedAt: String? { status?.csvExportedAt }
    /// Since when a fresh export has waited to be imported (as served).
    public var exportPendingSince: String? { status?.exportPending }
    /// The server's log file, for Show Log.
    public var logFile: URL { configuration.logFile }
    /// The data folder the server reports, else the one it was started on.
    public var dataFolderPath: String { settings?.dataDir ?? configuration.dataFolder.plainPath }

    // MARK: Life

    /// Starts the server and follows it. The controller takes the first-run backup before every launch. Safe to
    /// call more than once; does nothing once a shutdown has begun.
    public func start() async {
        guard !started, !shuttingDown else { return }
        started = true
        let updates = await controller.stateUpdates()
        stateTask = Task { [weak self] in
            for await state in updates {
                guard let self else { return }
                self.apply(state)
                self.backupOutcome = await self.controller.backupOutcome
            }
        }
        await controller.start()
    }

    /// Try Again after a failure or a locked data folder (the backup is retried first, by the controller).
    public func tryAgain() async {
        guard !shuttingDown else { return }
        await controller.tryAgain()
    }

    /// Stops the server cleanly (the app's quit waits for this). Nothing starts a server afterwards.
    public func shutdown() async {
        shuttingDown = true
        eventTask?.cancel()
        eventTask = nil
        await controller.stop()
        apply(await controller.state)
    }

    /// Settings ▸ Restore backup: stop the server, put the first-run backup back, start it again. Returns the folder
    /// where the replaced files were put aside. The restore is all or nothing (`BackupManager.restore`): when it
    /// throws, the folder is as it was, so the server is started on it again either way. A successful restore moves
    /// `restoreCount`, so stores reload even though no import happened.
    @discardableResult
    public func restoreBackup() async throws -> URL {
        eventTask?.cancel()
        eventTask = nil
        await controller.stop()
        let backups = backups
        let result = await Task.detached(priority: .userInitiated) { Result { try backups.restore() } }.value
        if case .success = result { restoreCount += 1 }
        if !shuttingDown { await controller.start() }
        return try result.get()
    }

    // MARK: Following the server

    private func apply(_ state: ServerState) {
        serverState = state
        guard let connection = state.connection else {
            eventTask?.cancel()
            eventTask = nil
            client = nil
            eventStreamConnected = false
            return
        }
        let client = makeClient(connection)
        self.client = client
        apply(status: connection.status, reload: false)
        eventTask?.cancel()
        let log = controller.log
        let events = EventClient(client: client) { type in log.write("ignored an event of a newer type: \(type)", source: "app") }
        eventTask = Task { [weak self] in
            await events.run { signal in await self?.handle(signal) }
        }
        Task { await reloadAll() }
    }

    /// Applies one signal from the event stream.
    public func handle(_ signal: EventSignal) async {
        switch signal {
        case .connected:
            eventStreamConnected = true
        case .disconnected:
            eventStreamConnected = false
        case .malformed(let type):
            eventProblems.append(EventProblem(type: type, at: .now))
            controller.log.write("an event of type \(type) did not decode; re-reading the status", source: "app")
            await reloadStatus()
        case .event(let event):
            await apply(event)
        }
    }

    private func apply(_ event: Components.Schemas.ServerEvent) async {
        if let hello = event.value1 {
            apply(status: hello.status, reload: true)
        } else if event.value2 != nil {
            status?.importing = true
            status?.importProgress = nil
            status?.lastError = nil
        } else if let progress = event.value3 {
            status?.importing = true
            status?.importProgress = progress.progress
        } else if let finished = event.value4 {
            if var next = status {
                next.importing = false
                next.importProgress = nil
                next.lastError = finished.error
                if let lastImport = finished.lastImport { next.lastImport = lastImport }
                apply(status: next, reload: true)
            }
            // The status says the rest (the export's time, a pending export)
            await reloadStatus()
        } else if let pending = event.value5 {
            status?.exportPending = pending.since
        }
        // `job` (value6): the storylines and briefing jobs arrive with N13
    }

    private func apply(status next: Components.Schemas.ServerStatus, reload: Bool) {
        status = next
        let stamp = next.lastImport?.finishedAt ?? ""
        guard stamp != importStamp else { return }
        importStamp = stamp
        if reload { Task { await reloadAll() } }
    }

    /// Re-reads `/api/status`.
    public func reloadStatus() async {
        guard let client else { return }
        do {
            apply(status: try await client.getStatus().ok.body.json, reload: true)
        } catch {
            note(error, reading: "status")
        }
    }

    /// Re-reads the settings, the clubs and the data status, and resolves the current club again.
    public func reloadAll() async {
        guard let client else { return }
        async let settingsAnswer = client.getSettings()
        async let orgsAnswer = client.listOrgs()
        async let dataStatusAnswer = client.getDataStatus()
        do {
            settings = try await settingsAnswer.ok.body.json
        } catch {
            note(error, reading: "settings")
        }
        do {
            orgs = try await orgsAnswer.ok.body.json
        } catch {
            note(error, reading: "clubs")
        }
        do {
            dataStatus = try await dataStatusAnswer.ok.body.json
        } catch {
            note(error, reading: "data status")
        }
        club = CurrentClub.from(served: settings?.organization, orgs: orgs)
    }

    private func note(_ error: any Error, reading what: String) {
        lastRequestError = "\(what): \(error)"
        controller.log.write("could not read the \(what): \(error)", source: "app")
    }
}
