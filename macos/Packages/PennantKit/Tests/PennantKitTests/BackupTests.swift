import Foundation
import PennantAPI
import Testing
@testable import PennantKit

/// The first-run backup (SWIFTUI_REBUILD.md section 7.5): once per data folder, never `league.db`, the database with
/// its write-ahead companions, nothing while another server holds the folder, and a restore that puts the files
/// back and sets the replaced ones aside.
@Suite("The first-run backup")
struct BackupTests {
    private func folder(with files: [String: String]) throws -> URL {
        let folder = try scratchFolder("backup")
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appending(path: name))
        }
        return folder
    }

    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    @Test("it copies the four files that exist, with the database's companions, and never league.db")
    func copies() throws {
        let data = try folder(with: [
            "league.db": "league", "league.db-wal": "league wal", "history.db": "history", "history.db-wal": "history wal",
            "history.db-shm": "history shm", "settings.json": "{\"theme\":\"dark\"}", "config.json": "{}",
        ])
        let backups = BackupManager(dataFolder: data)
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10)))
        guard case .backedUp(let record) = try backups.backUpIfFirstRun(now: now) else {
            Issue.record("no backup")
            return
        }
        #expect(record.folder == "pre-swiftui-2026-09-26")
        #expect(record.files == ["history.db", "history.db-wal", "history.db-shm", "settings.json", "config.json"])
        let copy = backups.backupsFolder.appending(path: record.folder)
        #expect(read(copy.appending(path: "history.db")) == "history")
        #expect(read(copy.appending(path: "history.db-wal")) == "history wal")
        #expect(read(copy.appending(path: "settings.json")) == "{\"theme\":\"dark\"}")
        let copied = try FileManager.default.contentsOfDirectory(atPath: copy.path)
        #expect(copied.contains { $0.hasPrefix("league") } == false)
        #expect(copied.contains("credentials.json") == false)
        #expect(BackupManager.files.contains("league.db") == false)
    }

    @Test("it happens once: the second start finds the record and copies nothing")
    func once() throws {
        let data = try folder(with: ["history.db": "first"])
        let backups = BackupManager(dataFolder: data)
        guard case .backedUp(let record) = try backups.backUpIfFirstRun() else {
            Issue.record("no backup")
            return
        }
        try Data("changed".utf8).write(to: data.appending(path: "history.db"))
        #expect(try backups.backUpIfFirstRun() == .alreadyDone(record))
        let folders = try FileManager.default.contentsOfDirectory(atPath: backups.backupsFolder.path)
        #expect(folders.filter { $0.hasPrefix("pre-swiftui-") && !$0.hasSuffix(".json") } == [record.folder])
        #expect(read(backups.backupsFolder.appending(path: "\(record.folder)/history.db")) == "first")
    }

    @Test("an empty data folder is recorded as backed up, with no files")
    func emptyFolder() throws {
        let backups = BackupManager(dataFolder: try folder(with: [:]))
        guard case .backedUp(let record) = try backups.backUpIfFirstRun() else {
            Issue.record("no backup")
            return
        }
        #expect(record.files.isEmpty)
        #expect(backups.record() == record)
    }

    @Test("a folder held by a running server is not backed up yet, and not recorded")
    func folderInUse() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let data = try folder(with: [
            "history.db": "history",
            "server.lock": #"{"pid":\#(pid),"startedAt":"2026-09-26T10:00:00.000Z","app":"Pennant (Electron)"}"#,
        ])
        let backups = BackupManager(dataFolder: data)
        #expect(backups.folderIsInUse())
        #expect(try backups.backUpIfFirstRun() == .folderInUse)
        #expect(backups.record() == nil)
    }

    @Test("a lock left by a process that has gone does not block the backup")
    func staleLock() throws {
        let data = try folder(with: [
            "history.db": "history",
            "server.lock": #"{"pid":99999999,"startedAt":"2026-09-26T10:00:00.000Z","app":"Pennant (Mac sidecar)"}"#,
        ])
        let backups = BackupManager(dataFolder: data)
        #expect(backups.folderIsInUse() == false)
        guard case .backedUp = try backups.backUpIfFirstRun() else {
            Issue.record("no backup")
            return
        }
    }

    @Test("restore puts the files back, sets the replaced ones aside with a stale -wal, and leaves league.db alone")
    func restore() throws {
        let data = try folder(with: ["history.db": "before", "settings.json": "old settings", "league.db": "league"])
        let backups = BackupManager(dataFolder: data)
        _ = try backups.backUpIfFirstRun()
        try Data("after".utf8).write(to: data.appending(path: "history.db"))
        try Data("after wal".utf8).write(to: data.appending(path: "history.db-wal"))
        try Data("new settings".utf8).write(to: data.appending(path: "settings.json"))
        try Data("new league".utf8).write(to: data.appending(path: "league.db"))
        try Data("{}".utf8).write(to: data.appending(path: "credentials.json"))

        let aside = try backups.restore()
        #expect(read(data.appending(path: "history.db")) == "before")
        #expect(FileManager.default.fileExists(atPath: data.appending(path: "history.db-wal").path) == false)
        #expect(read(data.appending(path: "settings.json")) == "old settings")
        #expect(read(data.appending(path: "league.db")) == "new league")
        // A file the backup did not have is left where it is
        #expect(read(data.appending(path: "credentials.json")) == "{}")
        #expect(read(aside.appending(path: "history.db")) == "after")
        #expect(read(aside.appending(path: "history.db-wal")) == "after wal")
        #expect(read(aside.appending(path: "settings.json")) == "new settings")
    }

    @Test("restore without a backup, or while a server holds the folder, refuses")
    func restoreRefuses() throws {
        let data = try folder(with: ["history.db": "x"])
        let backups = BackupManager(dataFolder: data)
        #expect(throws: BackupManager.BackupError.noBackup) { try backups.restore() }
        _ = try backups.backUpIfFirstRun()
        let pid = ProcessInfo.processInfo.processIdentifier
        try Data(#"{"pid":\#(pid)}"#.utf8).write(to: data.appending(path: "server.lock"))
        #expect(throws: BackupManager.BackupError.folderInUse) { try backups.restore() }
    }
}

@Suite("The server log")
struct ServerLogTests {
    @Test("it rotates past its size and keeps a fixed number of old files")
    func rotation() throws {
        let folder = try scratchFolder("log")
        let log = ServerLog(folder: folder, maxBytes: 400, keep: 2)
        for n in 0..<40 { log.write("line \(n) " + String(repeating: "x", count: 40)) }
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: log.url.path))
        #expect(manager.fileExists(atPath: log.rotated(1).path))
        #expect(manager.fileExists(atPath: log.rotated(2).path))
        #expect(manager.fileExists(atPath: log.rotated(3).path) == false)
        let size = try #require(try manager.attributesOfItem(atPath: log.url.path)[.size] as? Int)
        #expect(size <= 400)
        let newest = try String(contentsOf: log.url, encoding: .utf8)
        #expect(newest.contains("line 39"))
    }
}

@Suite("Served numbers without a display string")
struct ServedFormatTests {
    let us = Locale(identifier: "en_US")

    @Test("a count is grouped, and nil stays nil")
    func count() {
        #expect(ServedFormat.count(12_480, locale: us) == "12,480")
        #expect(ServedFormat.count(0, locale: us) == "0")
        #expect(ServedFormat.count(nil, locale: us) == nil)
    }

    @Test("a share needs a known, non-empty whole")
    func share() {
        #expect(ServedFormat.share(21, of: 50, locale: us) == "42%")
        #expect(ServedFormat.share(1, of: 0, locale: us) == nil)
        #expect(ServedFormat.share(nil, of: 10, locale: us) == nil)
        #expect(ServedFormat.share(3, of: nil, locale: us) == nil)
    }
}

/// Remembers whether the first-run backup existed when each process was spawned.
final class SpawnLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _backedUpAtSpawn: [Bool] = []
    var backedUpAtSpawn: [Bool] { lock.withLock { _backedUpAtSpawn } }
    func record(_ value: Bool) { lock.withLock { _backedUpAtSpawn.append(value) } }
}

/// Every launch is gated on the first-run backup being done or recorded (review B1), and a backup that fails starts
/// no server (review S1).
@Suite("The first-run backup gates every launch")
struct BackupGateTests {
    let status: Components.Schemas.ServerStatus

    init() throws {
        status = try fixtureStatus()
    }

    private func controller(_ configuration: ServerConfiguration, _ spawns: SpawnLog) -> (ServerController, FakeLauncher) {
        let data = configuration.dataFolder
        let launcher = FakeLauncher { process, _ in
            spawns.record(BackupManager(dataFolder: data).record() != nil)
            process.ready()
        }
        let status = status
        return (
            ServerController(configuration: configuration, launcher: launcher, keySource: NoKeys(), probe: { _, _ in status }, timing: fastTiming),
            launcher
        )
    }

    @Test("locked by another app with no backup yet: nothing starts; unlocked, Try Again backs up before it launches")
    func tryAgainAfterLocked() async throws {
        let configuration = try fakeConfiguration()
        try FileManager.default.createDirectory(at: configuration.dataFolder, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: configuration.dataFolder.appending(path: "history.db"))
        let lock = configuration.dataFolder.appending(path: "server.lock")
        try Data(#"{"pid":\#(getpid()),"startedAt":"x","app":"Pennant (Electron)"}"#.utf8).write(to: lock)
        let spawns = SpawnLog()
        let (controller, launcher) = controller(configuration, spawns)

        await controller.start()
        #expect(await controller.state == .locked(message: nil))
        #expect(await controller.backupOutcome == .folderInUse)
        #expect(launcher.launched.isEmpty)
        #expect(controller.backups.record() == nil)

        // The Electron app quits; the GM clicks Try Again
        try FileManager.default.removeItem(at: lock)
        await controller.tryAgain()
        try await waitForState(controller) { $0.connection != nil }
        #expect(spawns.backedUpAtSpawn == [true])
        let record = try #require(controller.backups.record())
        #expect(record.files == ["history.db"])
        await controller.stop()
    }

    @Test("the app model's Try Again goes through the same gate")
    @MainActor
    func appModelTryAgain() async throws {
        let configuration = try fakeConfiguration()
        try FileManager.default.createDirectory(at: configuration.dataFolder, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: configuration.dataFolder.appending(path: "history.db"))
        let lock = configuration.dataFolder.appending(path: "server.lock")
        try Data(#"{"pid":\#(getpid())}"#.utf8).write(to: lock)
        let spawns = SpawnLog()
        let (controller, _) = controller(configuration, spawns)
        let model = AppModel(configuration: configuration, controller: controller)
        await model.start()
        #expect(await eventually { model.serverState == .locked(message: nil) })
        #expect(await eventually { model.backupOutcome == .folderInUse })
        try FileManager.default.removeItem(at: lock)
        await model.tryAgain()
        #expect(await eventually { model.serverState.connection != nil })
        #expect(spawns.backedUpAtSpawn == [true])
        #expect(model.backups.record() != nil)
        await model.shutdown()
    }

    @Test("a backup that fails starts no server, leaves no partial backup, and Try Again retries it")
    func backupFailure() async throws {
        let configuration = try fakeConfiguration()
        let data = configuration.dataFolder
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("settings".utf8).write(to: data.appending(path: "settings.json"))
        let history = data.appending(path: "history.db")
        try Data("history".utf8).write(to: history)
        // Unreadable: the copy fails after settings.json… would have been copied
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: history.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: history.path) }
        let spawns = SpawnLog()
        let (controller, launcher) = controller(configuration, spawns)

        await controller.start()
        let state = await controller.state
        guard case .failed(let failure) = state else {
            Issue.record("expected a failure, got \(state)")
            return
        }
        #expect(failure.kind == .backupFailed)
        #expect(failure.detail != nil)
        #expect(launcher.launched.isEmpty)
        #expect(controller.backups.record() == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: controller.backups.backupsFolder.path)) ?? []
        #expect(leftovers.filter { $0.hasPrefix("pre-swiftui-") }.isEmpty)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: history.path)
        await controller.tryAgain()
        try await waitForState(controller) { $0.connection != nil }
        #expect(spawns.backedUpAtSpawn == [true])
        #expect(controller.backups.record()?.files == ["history.db", "settings.json"])
        await controller.stop()
    }

    @Test("after a shutdown has begun, the app model starts nothing")
    @MainActor
    func noStartAfterShutdown() async throws {
        let configuration = try fakeConfiguration()
        let spawns = SpawnLog()
        let (controller, launcher) = controller(configuration, spawns)
        let model = AppModel(configuration: configuration, controller: controller)
        await model.shutdown()
        await model.start()
        await model.tryAgain()
        #expect(launcher.launched.isEmpty)
    }
}

/// A restore is all or nothing (review S2).
@Suite("Restoring the backup")
struct RestoreTests {
    private func backedUpFolder() throws -> (BackupManager, BackupManager.Record) {
        let data = try scratchFolder("restore")
        try Data("before".utf8).write(to: data.appending(path: "history.db"))
        try Data("old settings".utf8).write(to: data.appending(path: "settings.json"))
        let backups = BackupManager(dataFolder: data)
        guard case .backedUp(let record) = try backups.backUpIfFirstRun() else { throw Timeout() }
        try Data("after".utf8).write(to: data.appending(path: "history.db"))
        try Data("after wal".utf8).write(to: data.appending(path: "history.db-wal"))
        try Data("new settings".utf8).write(to: data.appending(path: "settings.json"))
        return (backups, record)
    }

    private func read(_ backups: BackupManager, _ name: String) -> String? {
        try? String(contentsOf: backups.dataFolder.appending(path: name), encoding: .utf8)
    }

    private func untouched(_ backups: BackupManager) {
        #expect(read(backups, "history.db") == "after")
        #expect(read(backups, "history.db-wal") == "after wal")
        #expect(read(backups, "settings.json") == "new settings")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.dataFolder.path)) ?? []
        #expect(names.contains { $0.hasPrefix(".restore-") } == false)
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: backups.backupsFolder.path)) ?? []
        #expect(kept.contains { $0.hasPrefix("before-restore-") } == false)
    }

    @Test("a file missing from the backup: nothing is touched")
    func missingSource() throws {
        let (backups, record) = try backedUpFolder()
        try FileManager.default.removeItem(at: backups.backupsFolder.appending(path: "\(record.folder)/history.db"))
        #expect(throws: BackupManager.BackupError.backupIncomplete(missing: "history.db")) { try backups.restore() }
        untouched(backups)
    }

    @Test("an unreadable file in the backup: nothing is touched")
    func unreadableSource() throws {
        let (backups, record) = try backedUpFolder()
        let copy = backups.backupsFolder.appending(path: "\(record.folder)/settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: copy.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy.path) }
        #expect(throws: BackupManager.BackupError.backupIncomplete(missing: "settings.json")) { try backups.restore() }
        untouched(backups)
    }

    @Test("a failure in the middle of the swap puts every original back")
    func failureMidSwap() throws {
        struct Injected: Error {}
        let (backups, _) = try backedUpFolder()
        #expect(throws: Injected.self) {
            try backups.restore(now: .now) { name in if name == "settings.json" { throw Injected() } }
        }
        untouched(backups)
    }

    @Test("a whole restore swaps every file and sets the replaced ones aside")
    func whole() throws {
        let (backups, _) = try backedUpFolder()
        let aside = try backups.restore()
        #expect(read(backups, "history.db") == "before")
        #expect(read(backups, "settings.json") == "old settings")
        #expect(FileManager.default.fileExists(atPath: backups.dataFolder.appending(path: "history.db-wal").path) == false)
        #expect((try? String(contentsOf: aside.appending(path: "history.db-wal"), encoding: .utf8)) == "after wal")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.dataFolder.path)) ?? []
        #expect(names.contains { $0.hasPrefix(".restore-") } == false)
    }

    @Test("the app model restarts the server after a failed restore, on the untouched folder")
    @MainActor
    func appModelAfterFailure() async throws {
        let configuration = try fakeConfiguration()
        try FileManager.default.createDirectory(at: configuration.dataFolder, withIntermediateDirectories: true)
        try Data("before".utf8).write(to: configuration.dataFolder.appending(path: "history.db"))
        let status = try fixtureStatus()
        let launcher = FakeLauncher { process, _ in process.ready() }
        let controller = ServerController(configuration: configuration, launcher: launcher, keySource: NoKeys(), probe: { _, _ in status }, timing: fastTiming)
        let model = AppModel(configuration: configuration, controller: controller)
        await model.start()
        #expect(await eventually { model.serverState.connection != nil })
        let record = try #require(model.backups.record())
        try Data("after".utf8).write(to: configuration.dataFolder.appending(path: "history.db"))
        try FileManager.default.removeItem(at: model.backups.backupsFolder.appending(path: "\(record.folder)/history.db"))
        await #expect(throws: BackupManager.BackupError.self) { try await model.restoreBackup() }
        #expect(model.restoreCount == 0)
        #expect(await eventually { model.serverState.connection != nil })
        #expect((try? String(contentsOf: configuration.dataFolder.appending(path: "history.db"), encoding: .utf8)) == "after")
        await model.shutdown()
    }
}
