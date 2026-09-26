import Foundation
import OpenAPIRuntime
import PennantAPI
import Testing
@testable import PennantKit

/// `AppModel` over a scripted server and the captured answers: it follows the server's state, reads the status,
/// settings, clubs and data status, resolves the club, applies events, and re-reads the status when a known event
/// does not decode.
@Suite("The app model")
@MainActor
struct AppModelTests {
    private func model(events sse: String, status: Components.Schemas.ServerStatus) throws -> (AppModel, RoutedTransport) {
        let transport = RoutedTransport([
            "/api/status": try RoutedTransport.json("getStatus"),
            "/api/settings": try RoutedTransport.json("getSettings"),
            "/api/orgs": try RoutedTransport.json("listOrgs"),
            "/api/data-status": try RoutedTransport.json("getDataStatus"),
            "/api/v2/events": RoutedTransport.sse(sse),
        ])
        let configuration = try fakeConfiguration()
        let controller = ServerController(
            configuration: configuration,
            launcher: FakeLauncher { process, _ in process.ready() },
            keySource: NoKeys(),
            probe: { _, _ in status },
            timing: fastTiming
        )
        let model = AppModel(configuration: configuration, controller: controller) { connection in
            PennantClient.make(port: connection.port, token: connection.token, transport: transport)
        }
        return (model, transport)
    }

    @Test("ready: the status, the settings, the clubs, the data status and the club the save's human manages")
    func followsTheServer() async throws {
        let status = try fixtureStatus()
        let (model, transport) = try model(events: "", status: status)
        await model.start()
        #expect(await eventually { model.club != nil && model.dataStatus != nil })
        #expect(model.serverState.connection != nil)
        #expect(model.status == status)
        #expect(model.settings?.dataDir == "/tmp/ootp-fo-test")
        #expect(model.dataFolderPath == "/tmp/ootp-fo-test")
        #expect(model.orgs.count == 4)
        #expect(model.club?.ref == ClubRef(id: 1))
        #expect(model.club?.org?.label == "Club 1 N")
        #expect(model.club?.source == .humanManaged)
        #expect(transport.paths.contains("/api/v2/events"))
        await model.shutdown()
        #expect(model.serverState == .stopped)
        #expect(model.client == nil)
    }

    @Test("import-progress and import-finished events update the served status")
    func importProgress() async throws {
        let status = try fixtureStatus()
        let (model, transport) = try model(events: "", status: status)
        await model.start()
        #expect(await eventually { model.club != nil })

        let progress = try JSONDecoder().decode(Components.Schemas.ServerEvent.self, from: Data(
            #"{"type":"import-progress","progress":{"table":"players","fileIndex":2,"files":70,"rows":1200,"phase":"writing"}}"#.utf8
        ))
        await model.handle(.event(progress))
        #expect(model.isImporting)
        #expect(model.importProgress?.table == "players")

        let finished = try JSONDecoder().decode(Components.Schemas.ServerEvent.self, from: Data(
            #"{"type":"import-finished","lastImport":{"tables":70,"rows":9000,"startedAt":"2040-07-02T10:00:00.000Z","finishedAt":"2040-07-02T10:01:00.000Z","files":[]},"error":null}"#.utf8
        ))
        let before = transport.paths.filter { $0 == "/api/status" }.count
        await model.handle(.event(finished))
        #expect(transport.paths.filter { $0 == "/api/status" }.count == before + 1)
        #expect(model.isImporting == false)
        #expect(model.importProgress == nil)

        let pending = try JSONDecoder().decode(Components.Schemas.ServerEvent.self, from: Data(
            #"{"type":"export-pending","since":"2040-07-03T09:00:00.000Z"}"#.utf8
        ))
        await model.handle(.event(pending))
        #expect(model.exportPendingSince == "2040-07-03T09:00:00.000Z")
        await model.shutdown()
    }

    @Test("the import stamp follows the last import's finish, not every status")
    func importStamp() async throws {
        let status = try fixtureStatus()
        let (model, _) = try model(events: "", status: status)
        await model.start()
        #expect(await eventually { model.club != nil })
        #expect(model.importStamp == "")
        var imported = status
        imported.lastImport = Components.Schemas.ImportResult(
            tables: 1, rows: 2, startedAt: "2040-07-02T10:00:00.000Z", finishedAt: "2040-07-02T10:01:00.000Z", files: []
        )
        let hello = Components.Schemas.ServerEvent(value1: .init(_type: .hello, status: imported))
        await model.handle(.event(hello))
        #expect(model.importStamp == "2040-07-02T10:01:00.000Z")
        await model.shutdown()
    }

    @Test("a known event that did not decode is reported and the status is read again")
    func malformedEvent() async throws {
        let status = try fixtureStatus()
        let (model, transport) = try model(events: "", status: status)
        await model.start()
        #expect(await eventually { model.club != nil })
        let before = transport.paths.filter { $0 == "/api/status" }.count
        await model.handle(.malformed(type: "hello"))
        #expect(model.eventProblems.map(\.type) == ["hello"])
        #expect(transport.paths.filter { $0 == "/api/status" }.count == before + 1)
        await model.shutdown()
    }

    @Test("the first start on a data folder takes the backup; the next start does not")
    func backupOnce() async throws {
        let status = try fixtureStatus()
        let (model, _) = try model(events: "", status: status)
        try FileManager.default.createDirectory(at: model.configuration.dataFolder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: model.configuration.dataFolder.appending(path: "settings.json"))
        await model.start()
        #expect(await eventually { model.backupOutcome != nil })
        guard case .backedUp(let record) = model.backupOutcome else {
            Issue.record("no backup: \(String(describing: model.backupOutcome))")
            return
        }
        #expect(record.files == ["settings.json"])
        await model.shutdown()

        let again = AppModel(configuration: model.configuration, controller: ServerController(
            configuration: model.configuration, launcher: FakeLauncher { process, _ in process.ready() },
            keySource: NoKeys(), probe: { _, _ in status }, timing: fastTiming
        ))
        await again.start()
        #expect(await eventually { again.backupOutcome == .alreadyDone(record) })
        await again.shutdown()
    }
}

@Suite("The current club")
struct CurrentClubTests {
    private func orgs() throws -> [Components.Schemas.Org] {
        try JSONDecoder().decode([Components.Schemas.Org].self, from: fixtureData("responses/listOrgs.json"))
    }

    private func served(_ json: String) throws -> Components.Schemas.CurrentOrganization {
        try JSONDecoder().decode(Components.Schemas.CurrentOrganization.self, from: Data(json.utf8))
    }

    @Test("the captured settings serve the human-managed club, and the app takes it as served")
    func capturedSettings() throws {
        let settings = try JSONDecoder().decode(
            Components.Schemas.SettingsResponse.self, from: fixtureData("responses/getSettings.json")
        )
        let club = CurrentClub.from(served: settings.organization, orgs: try orgs())
        #expect(club?.ref == ClubRef(id: 1))
        #expect(club?.source == .humanManaged)
        #expect(club?.org?.label == "Club 1 N")
    }

    @Test("a configured club the list does not have stays the served club, never swapped for the human-managed one")
    func configuredNotInList() throws {
        let club = CurrentClub.from(served: try served(#"{"id":999,"source":"configured"}"#), orgs: try orgs())
        #expect(club?.ref == ClubRef(id: 999))
        #expect(club?.source == .configured)
        #expect(club?.org == nil)
    }

    @Test("a configured club in the list is found there")
    func configured() throws {
        let club = CurrentClub.from(served: try served(#"{"id":3,"source":"configured"}"#), orgs: try orgs())
        #expect(club?.org?.label == "Club 3 N")
    }

    @Test("no served club is no club, never a guess; a newer source is kept as it came")
    func noneOrNewer() throws {
        #expect(CurrentClub.from(served: nil, orgs: try orgs()) == nil)
        let club = CurrentClub.from(served: try served(#"{"id":2,"source":"commissioner"}"#), orgs: try orgs())
        #expect(club?.source == .other("commissioner"))
    }
}
