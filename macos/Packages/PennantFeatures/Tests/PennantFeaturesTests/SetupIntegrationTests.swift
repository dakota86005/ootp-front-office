import Foundation
import PennantAPI
import PennantKit
import Setup
import Shell
import Testing

/// The staged server and the synthetic league the test runs on.
enum StagedServer {
    nonisolated static let stage = PreviewFixtures.repositoryRoot.appending(path: "build/macos-server", directoryHint: .isDirectory)
    nonisolated static var league: URL? {
        ProcessInfo.processInfo.environment["PENNANT_TEST_LEAGUE"].map { URL(fileURLWithPath: $0) }
    }

    nonisolated static var available: Bool {
        guard let league else { return false }
        let manager = FileManager.default
        return manager.isExecutableFile(atPath: stage.appending(path: "Helpers/pennant-server").path)
            && manager.fileExists(atPath: stage.appending(path: "Resources/server/server.cjs").path)
            && manager.fileExists(atPath: league.path)
    }
}

/// The Setup flow against the real server, as the app runs it: the staged bundle (`npm run mac:stage`), a scratch
/// data folder with the synthetic league, the app's model following the event stream, and a pretend OOTP save whose
/// export is one small table. The folder is picked by path, the save chosen, the import followed to its end, and a club
/// saved; the server then serves that club as the configured one.
///
/// It runs when the staged server exists and `PENNANT_TEST_LEAGUE` names a synthetic `league.db`
/// (`macos/scripts/test.sh` sets both up). Never point it at a real save.
@MainActor
@Suite("Setup on the real server", .serialized, .enabled(if: StagedServer.available))
struct SetupIntegrationTests {
    private func scratch() throws -> URL {
        let base = ProcessInfo.processInfo.environment["PENNANT_TEST_SCRATCH"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "setup-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func until(_ timeout: Duration = .seconds(60), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    @Test("pick a folder, import the save, pick a club: the server serves that club afterwards")
    func setupFlow() async throws {
        let run = try scratch()
        let data = run.appending(path: "data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try #require(StagedServer.league), to: data.appending(path: "league.db"))
        // A pretend OOTP save: the .lg folder with an export of one small table
        let save = run.appending(path: "saves/Synthetic League.lg", directoryHint: .isDirectory)
        let csv = save.appending(path: "import_export/csv", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: csv, withIntermediateDirectories: true)
        try Data("id,note\n1,one\n2,two\n".utf8).write(to: csv.appending(path: "zz_setup_check.csv"))

        let configuration = ServerConfiguration(
            nodeExecutable: StagedServer.stage.appending(path: "Helpers/pennant-server"),
            serverRoot: StagedServer.stage.appending(path: "Resources/server", directoryHint: .isDirectory),
            dataFolder: data,
            logFolder: run.appending(path: "logs", directoryHint: .isDirectory),
            appVersion: "0.0.0-integration"
        )
        let model = AppModel(configuration: configuration, controller: ServerController(configuration: configuration, keySource: NoKeys()))
        await model.start()
        #expect(await until { model.isReady && model.settings != nil }, "not ready; see \(configuration.logFile.path)")
        #expect(model.needsSetup)

        let setup = SetupModel(client: { model.client }, onClubSaved: { await model.reloadAll() })
        await setup.load()
        #expect(setup.savesLoaded)

        setup.folderPath = save.path(percentEncoded: false)
        await setup.useFolder(status: model.status)
        #expect(setup.folderProblem == nil)
        #expect(setup.chosen?.name == "Synthetic League")

        let landed = await until {
            await setup.observe(model.status)
            return setup.step != .importing || setup.importProblem != nil
        }
        #expect(landed)
        #expect(setup.importProblem == nil)
        #expect(setup.step == .pickClub)
        #expect(setup.clubs.first?.isHuman == true)
        #expect(setup.selectedClub == setup.clubs.first?.teamId)

        let other = try #require(setup.clubs.first { !$0.isHuman })
        setup.selectedClub = other.teamId
        await setup.saveClub()
        #expect(setup.step == .done)
        #expect(model.club?.ref == ClubRef(id: other.teamId))
        #expect(model.club?.source == .configured)
        #expect(model.status?.configured == true)
        #expect(!model.needsSetup)

        await model.shutdown()
        #expect(!FileManager.default.fileExists(atPath: data.appending(path: "server.lock").path))
    }
}
