import Foundation
import HTTPTypes
import OpenAPIRuntime
import PennantAPI
import PennantKit
import Setup
import Shell
import Testing

/// A server the test scripts: each operation answers with a status and a JSON body, and every request is recorded.
final class StubServer: ClientTransport, @unchecked Sendable {
    struct Request: Sendable {
        var operation: String
        var body: Data?
    }

    private let lock = NSLock()
    private var answers: [String: [(Int, String)]] = [:]
    private var _requests: [Request] = []

    var requests: [Request] { lock.withLock { _requests } }

    /// Answers `operation` with these (status, JSON) pairs in turn; the last one repeats.
    func answer(_ operation: String, _ replies: (Int, String)...) {
        lock.withLock { answers[operation] = replies }
    }

    /// Answers `operation` with a captured response from `contract/fixtures/responses/`.
    func answer(_ operation: String, fixture name: String, status: Int = 200) throws {
        let json = try String(contentsOf: PreviewFixtures.responses.appending(path: "\(name).json"), encoding: .utf8)
        answer(operation, (status, json))
    }

    func bodies(of operation: String) -> [[String: Any]] {
        requests.filter { $0.operation == operation }.compactMap { request in
            request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var data: Data?
        if let body { data = try await Data(collecting: body, upTo: 1 << 20) }
        let reply: (Int, String) = lock.withLock {
            _requests.append(Request(operation: operationID, body: data))
            guard var queue = answers[operationID], let first = queue.first else { return (404, #"{"error":"not scripted"}"#) }
            if queue.count > 1 { queue.removeFirst(); answers[operationID] = queue }
            return first
        }
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        return (HTTPResponse(status: .init(code: reply.0), headerFields: fields), HTTPBody(reply.1))
    }
}

private func status(
    importing: Bool = false,
    progress: Components.Schemas.ImportProgress? = nil,
    finishedAt: String? = nil,
    lastError: String? = nil,
    csvDirExists: Bool = true
) throws -> Components.Schemas.ServerStatus {
    var status = try #require(PreviewFixtures.status(configured: true))
    status.importing = importing
    status.importProgress = progress
    status.lastError = lastError
    status.csvDirExists = csvDirExists
    status.lastImport = finishedAt.map {
        .init(tables: 1, rows: 3, startedAt: "2040-07-01T11:59:00.000Z", finishedAt: $0, files: [])
    }
    return status
}

private func json(_ status: Components.Schemas.ServerStatus) throws -> String {
    String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
}

@MainActor
@Suite("The Setup window's steps")
struct SetupModelTests {
    let server = StubServer()
    let client: Client

    init() throws {
        client = PennantClient.make(port: 1, token: String(repeating: "t", count: 64), transport: server)
        try server.answer("listSaves", fixture: "listSaves")
        server.answer("getSearchLocations", (200, #"{"platform":"darwin","locations":[{"label":"OOTP 27","path":"/tmp/saved_games","exists":true}]}"#))
        server.answer("setSave", (200, #"{"ok":true}"#))
        try server.answer("listOrgs", fixture: "listOrgs")
        try server.answer("getSettings", fixture: "getSettings")
        server.answer("saveSettings", (200, try String(contentsOf: PreviewFixtures.responses.appending(path: "saveSettings-club.json"), encoding: .utf8)))
    }

    func makeModel(onSaved: @escaping @MainActor () async -> Void = {}) -> SetupModel {
        let client = client
        return SetupModel(client: { client }, onClubSaved: onSaved)
    }

    @Test("finds the saves the server found and where it looked")
    func loads() async {
        let model = makeModel()
        await model.load()
        #expect(model.savesLoaded)
        #expect(model.saves.map(\.name) == ["Test League"])
        #expect(model.locations.map(\.label) == ["OOTP 27"])
    }

    @Test("a save chosen and imported leads to the club, the human-managed club first and preselected, and saving it closes Setup")
    func happyPath() async throws {
        var saved = false
        let model = makeModel { saved = true }
        await model.load()
        let before = try status(finishedAt: "2040-07-01T10:00:00.000Z")
        server.answer("getStatus", (200, try json(status(importing: true, finishedAt: "2040-07-01T10:00:00.000Z"))))
        await model.choose(model.saves[0], status: before)
        #expect(model.step == .importing)
        let body = try #require(server.bodies(of: "setSave").first)
        #expect(body["csvDir"] as? String == model.saves[0].csvDir)
        #expect(body["saveName"] as? String == "Test League")

        let progress = Components.Schemas.ImportProgress(table: "players", fileIndex: 3, files: 10, rows: 1200, phase: .init(value1: .writing))
        await model.observe(try status(importing: true, progress: progress, finishedAt: "2040-07-01T10:00:00.000Z"))
        #expect(model.progress == progress)
        #expect(model.step == .importing)

        await model.observe(try status(finishedAt: "2040-07-01T12:00:00.000Z"))
        #expect(model.step == .pickClub)
        #expect(model.clubs.first?.isHuman == true)
        #expect(model.selectedClub == 1)

        model.selectedClub = 3
        await model.saveClub()
        #expect(server.bodies(of: "saveSettings").first?["defaultOrgId"] as? Int == 3)
        #expect(saved)
        #expect(model.step == .done)
    }

    @Test("an import that fails shows the server's sentence, and Try Again imports again")
    func importFails() async throws {
        let model = makeModel()
        server.answer("getStatus", (200, try json(status(importing: true))))
        await model.choose(PreviewFixtures.saves[0], status: try status())
        await model.observe(try status(lastError: "players.csv could not be read"))
        #expect(model.importProblem == .served("players.csv could not be read"))
        #expect(model.step == .importing)

        server.answer("startImport", (200, #"{"ok":true,"lastImport":null,"lastError":null}"#))
        server.answer("getStatus", (200, try json(status(finishedAt: "2040-07-01T12:00:00.000Z"))))
        await model.retryImport(status: try status())
        #expect(model.importProblem == nil)
        #expect(model.step == .pickClub)
    }

    @Test("a save whose export folder is gone never starts importing, and says so without inventing a reason")
    func importDoesNotStart() async throws {
        let model = makeModel()
        server.answer("getStatus", (200, try json(status(csvDirExists: false))))
        await model.choose(PreviewFixtures.saves[0], status: try status())
        #expect(model.importProblem == .didNotStart)
        model.restart()
        #expect(model.step == .findSave)
        #expect(model.importProblem == nil)
    }

    @Test("a refused save shows the server's sentence and stays on the first step")
    func refusedSave() async throws {
        let model = makeModel()
        try server.answer("setSave", fixture: "setSave-no-folder", status: 400)
        await model.choose(PreviewFixtures.saves[0], status: nil)
        #expect(model.step == .findSave)
        #expect(model.folderProblem == "csvDir is required")
    }

    @Test("a picked folder that is an export is chosen at once")
    func folderIsExport() async throws {
        let model = makeModel()
        try server.answer("resolveFolder", fixture: "resolveFolder-export")
        server.answer("getStatus", (200, try json(status(importing: true))))
        model.folderPath = "/tmp/Test League.lg"
        await model.useFolder(status: try status())
        #expect(server.bodies(of: "resolveFolder").first?["path"] as? String == "/tmp/Test League.lg")
        #expect(model.step == .importing)
        #expect(model.chosen?.name == "Test League")
    }

    @Test("a picked folder of saves lists them; a folder the server cannot use shows its sentence")
    func folderChoicesAndRefusal() async throws {
        let model = makeModel()
        try server.answer("resolveFolder", fixture: "resolveFolder-saves")
        model.folderPath = "/tmp/saved_games"
        await model.useFolder(status: nil)
        #expect(model.folderChoices?.map(\.name) == ["Test League"])
        #expect(model.step == .findSave)

        try server.answer("resolveFolder", fixture: "resolveFolder-no-folder", status: 400)
        await model.useFolder(status: nil)
        #expect(model.folderChoices == nil)
        #expect(model.folderProblem == "No folder given.")
    }

    @Test("a status from before the import is not mistaken for its end")
    func waitsForItsOwnImport() async throws {
        let model = makeModel()
        server.answer("getStatus", (200, try json(status(finishedAt: "2040-07-01T10:00:00.000Z"))))
        await model.choose(PreviewFixtures.saves[0], status: try status(finishedAt: "2040-07-01T10:00:00.000Z"))
        #expect(model.step == .importing)
        #expect(model.importProblem == nil)
        await model.observe(try status(finishedAt: "2040-07-01T10:00:00.000Z", lastError: "an older failure"))
        #expect(model.step == .importing)
        #expect(model.importProblem == nil)
    }
}
