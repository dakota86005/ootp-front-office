import Darwin
import Foundation

/// The backup taken the first time the Mac app starts on a data folder (SWIFTUI_REBUILD.md section 7.5, D-055):
/// `history.db` (the irreplaceable rating history), `settings.json`, `config.json` and `credentials.json`, whichever
/// exist, copied to `backups/pre-swiftui-<date>/` before the server starts. `league.db` is re-imported from the
/// export and is never copied.
///
/// `history.db` is kept in SQLite's write-ahead log mode, so its `-wal` and `-shm` files are copied with it: with no
/// server running, the three together are a consistent database. A folder whose lock is held by a running server
/// (the Electron app) is not backed up then, and no server is started on it (`ServerController` gates every launch,
/// Try Again included, on this backup being done or recorded). `backups/pre-swiftui.json` records that it was done,
/// so it happens once per folder. A backup that fails partway is removed, and no server starts.
public struct BackupManager: Sendable {
    public let dataFolder: URL

    /// The files backed up, in this order. Never `league.db`.
    public static let files = ["history.db", "settings.json", "config.json", "credentials.json"]
    /// SQLite's companions of a database in write-ahead log mode.
    static let sqliteCompanions = ["-wal", "-shm"]

    public init(dataFolder: URL) {
        self.dataFolder = dataFolder
    }

    public var backupsFolder: URL { dataFolder.appending(path: "backups", directoryHint: .isDirectory) }
    /// The record that the first-run backup was taken.
    public var recordFile: URL { backupsFolder.appending(path: "pre-swiftui.json") }

    /// What the first-run backup holds.
    public struct Record: Codable, Sendable, Equatable {
        /// The folder's name inside `backups/` (`pre-swiftui-2026-09-26`).
        public var folder: String
        public var createdAt: Date
        /// The files copied, companions included (`history.db-wal`).
        public var files: [String]
    }

    public enum Outcome: Sendable, Equatable {
        /// Backed up now.
        case backedUp(Record)
        /// Done on an earlier start.
        case alreadyDone(Record)
        /// Another program's server holds the folder; nothing was copied or recorded.
        case folderInUse
    }

    public enum BackupError: Error, Sendable, Equatable {
        case noBackup
        case folderInUse
        /// A file the record names is missing from the backup, or cannot be read; nothing was changed.
        case backupIncomplete(missing: String)
    }

    /// The record of the first-run backup, if it was taken.
    public func record() -> Record? {
        guard let data = try? Data(contentsOf: recordFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Record.self, from: data)
    }

    /// Takes the backup unless it was taken before. Call it before the server starts.
    public func backUpIfFirstRun(now: Date = .now) throws -> Outcome {
        if let existing = record() { return .alreadyDone(existing) }
        if folderIsInUse() { return .folderInUse }
        let manager = FileManager.default
        try manager.createDirectory(at: backupsFolder, withIntermediateDirectories: true)

        let destination = uniqueFolder(named: "pre-swiftui-\(Self.dayStamp(now))")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let record: Record
        do {
            var copied: [String] = []
            for name in Self.filesWithCompanions() where manager.fileExists(atPath: dataFolder.appending(path: name).path) {
                try manager.copyItem(at: dataFolder.appending(path: name), to: destination.appending(path: name))
                copied.append(name)
            }
            // Whole seconds, as the record file stores it
            let createdAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
            record = Record(folder: destination.lastPathComponent, createdAt: createdAt, files: copied)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: recordFile, options: .atomic)
        } catch {
            // A partial copy is not a backup: remove it, so the next attempt starts clean and nothing half-made
            // is ever taken for the real thing
            try? manager.removeItem(at: destination)
            throw error
        }
        return .backedUp(record)
    }

    /// Puts the backed-up files back, all or nothing. The server must be stopped first (the app stops it, restores,
    /// and starts it again).
    /// 1. Every file the record names must be in the backup and readable; otherwise nothing is touched.
    /// 2. They are copied into a staging folder inside the data folder (same volume, so the swap is renames).
    /// 3. The swap: what is in the folder now (a restored database's stale `-wal` and `-shm` included, so they cannot
    ///    be replayed over it) moves to `backups/before-restore-<time>/`, then the staged copies move in.
    /// If any step fails, what moved is moved back and the error is thrown: the folder is as it was, and always holds a
    /// usable `history.db`. Returns the folder holding the replaced files, so a restore can be undone by hand.
    @discardableResult
    public func restore(now: Date = .now) throws -> URL {
        try restore(now: now, beforeMovingIn: { _ in })
    }

    /// `beforeMovingIn` runs before each staged file moves into place (a test fails one to check the roll-back).
    func restore(now: Date, beforeMovingIn: (String) throws -> Void) throws -> URL {
        guard let record = record() else { throw BackupError.noBackup }
        if folderIsInUse() { throw BackupError.folderInUse }
        let manager = FileManager.default
        let source = backupsFolder.appending(path: record.folder, directoryHint: .isDirectory)
        // 1. The backup is whole
        for name in record.files where !manager.isReadableFile(atPath: source.appending(path: name).path) {
            throw BackupError.backupIncomplete(missing: name)
        }
        // 2. Staged next to the live files
        let staging = dataFolder.appending(path: ".restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        for name in record.files {
            try manager.copyItem(at: source.appending(path: name), to: staging.appending(path: name))
        }
        // 3. The swap, undone on any failure
        let aside = uniqueFolder(named: "before-restore-\(Self.timeStamp(now))")
        try manager.createDirectory(at: aside, withIntermediateDirectories: true)
        var movedAside: [String] = []
        var movedIn: [String] = []
        do {
            for name in Self.filesWithCompanions() {
                let current = dataFolder.appending(path: name)
                let restoresThis = record.files.contains(name)
                    || Self.sqliteCompanions.contains { name.hasSuffix($0) && record.files.contains(String(name.dropLast($0.count))) }
                guard restoresThis, manager.fileExists(atPath: current.path) else { continue }
                try manager.moveItem(at: current, to: aside.appending(path: name))
                movedAside.append(name)
            }
            for name in record.files {
                try beforeMovingIn(name)
                try manager.moveItem(at: staging.appending(path: name), to: dataFolder.appending(path: name))
                movedIn.append(name)
            }
        } catch {
            for name in movedIn { try? manager.removeItem(at: dataFolder.appending(path: name)) }
            for name in movedAside {
                try? manager.moveItem(at: aside.appending(path: name), to: dataFolder.appending(path: name))
            }
            try? manager.removeItem(at: aside)
            throw error
        }
        return aside
    }

    /// Whether `server.lock` names a process that is still running (the server's own test, `server/dataLock.ts`).
    public func folderIsInUse() -> Bool {
        let lock = dataFolder.appending(path: "server.lock")
        guard let data = try? Data(contentsOf: lock),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0 else { return false }
        return Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    static func filesWithCompanions() -> [String] {
        files.flatMap { name in
            name.hasSuffix(".db") ? [name] + sqliteCompanions.map { name + $0 } : [name]
        }
    }

    private func uniqueFolder(named base: String) -> URL {
        var candidate = backupsFolder.appending(path: base, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = backupsFolder.appending(path: "\(base)-\(n)", directoryHint: .isDirectory)
            n += 1
        }
        return candidate
    }

    /// The local date, `2026-09-26`.
    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The local date and time, `2026-09-26T101530` (no colons, which Finder shows as slashes).
    static func timeStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return dayStamp(date, calendar: calendar) + String(format: "T%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
