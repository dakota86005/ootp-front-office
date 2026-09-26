import Foundation
import Observation
import OpenAPIRuntime
import PennantAPI

/// The Setup window's steps (SWIFTUI_REBUILD.md section 3.1), as React's first run does them: find the save (the saves
/// the server found, where it looked, or a folder the GM picks), choose it (`POST /api/config`, which starts an
/// import), follow the import from the served status until it lands, then pick the club (the clubs as served, the one
/// the save's human manages first) and save it (`POST /api/settings`).
///
/// Every sentence it holds is the server's (`error` from a refusal, `lastError` from a failed import); the steps and
/// their labels are structural. It never decides which save or club is right: the GM does.
@Observable @MainActor
public final class SetupModel {
    public enum Step: Hashable, Sendable {
        case findSave
        case importing
        case pickClub
        /// The club is saved; the window closes.
        case done
    }

    /// Why an import did not land.
    public enum ImportProblem: Hashable, Sendable {
        /// The server's sentence (`lastError`, or a refusal's `error`).
        case served(String)
        /// The server took the save but no import began (its export folder was not there).
        case didNotStart
        /// The request itself failed.
        case request(String)
    }

    public private(set) var step: Step = .findSave
    /// `/api/saves`: the saves found in the usual places.
    public private(set) var saves: [Components.Schemas.SaveInfo] = []
    public private(set) var savesLoaded = false
    /// `/api/search-locations`: where the server looked.
    public private(set) var locations: [Components.Schemas.SearchLocation] = []
    /// A folder the GM typed or picked.
    public var folderPath = ""
    /// The saves inside the picked folder, when it holds several.
    public private(set) var folderChoices: [Components.Schemas.SaveInfo]?
    /// The server's sentence about the picked folder or the chosen save.
    public private(set) var folderProblem: String?
    /// The save being imported.
    public private(set) var chosen: Components.Schemas.SaveInfo?
    /// The import's progress as served.
    public private(set) var progress: Components.Schemas.ImportProgress?
    public private(set) var importProblem: ImportProblem?
    /// `/api/orgs`, the club the save's human manages first.
    public private(set) var clubs: [Components.Schemas.Org] = []
    public var selectedClub: Int?
    public private(set) var clubProblem: String?
    /// A request is under way.
    public private(set) var busy = false

    private var startStamp: String?
    private var sawImportRunning = false
    private let client: @MainActor () -> Client?
    private let onClubSaved: @MainActor () async -> Void

    /// - Parameters:
    ///   - client: the running server's client (nil while it is down).
    ///   - onClubSaved: runs after the club is saved, before the window closes (the app re-reads its settings).
    public init(client: @escaping @MainActor () -> Client?, onClubSaved: @escaping @MainActor () async -> Void = {}) {
        self.client = client
        self.onClubSaved = onClubSaved
    }

    // MARK: Find the save

    /// Back to the first step (Club ▸ Import Export…, or Choose Another Save).
    public func restart() {
        step = .findSave
        folderChoices = nil
        folderProblem = nil
        importProblem = nil
        progress = nil
        chosen = nil
        clubProblem = nil
        busy = false
    }

    /// Reads the saves the server found and where it looked.
    public func load() async {
        guard let client = client() else { return }
        async let savesAnswer = client.listSaves()
        async let locationsAnswer = client.getSearchLocations()
        saves = (try? await savesAnswer.ok.body.json) ?? []
        locations = (try? await locationsAnswer.ok.body.json.locations) ?? []
        savesLoaded = true
    }

    /// Checks the folder the GM typed or picked (`POST /api/resolve-folder`): an export or a save is chosen at once; a
    /// folder of saves lists them; anything else shows the server's sentence.
    public func useFolder(status: Components.Schemas.ServerStatus?) async {
        let path = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, let client = client() else { return }
        busy = true
        folderProblem = nil
        folderChoices = nil
        defer { busy = false }
        let result: Components.Schemas.ResolveResult
        do {
            switch try await client.resolveFolder(body: .json(.init(path: path))) {
            case .ok(let ok): result = try ok.body.json
            case .badRequest(let refused): result = try refused.body.json
            case .undocumented(let code, _):
                folderProblem = "HTTP \(code)"
                return
            }
        } catch {
            folderProblem = String(describing: error)
            return
        }
        if result.ok, let csvDir = result.csvDir {
            let save = Components.Schemas.SaveInfo(
                name: result.saveName ?? URL(fileURLWithPath: path).lastPathComponent,
                lgPath: path,
                csvDir: csvDir,
                csvCount: result.csvCount ?? 0,
                csvLastModified: nil
            )
            busy = false
            await choose(save, status: status)
        } else if let saves = result.saves, !saves.isEmpty {
            folderChoices = saves
        } else {
            folderProblem = result.error
        }
    }

    /// Chooses a save (`POST /api/config`); the server starts importing it, and the window follows the import.
    public func choose(_ save: Components.Schemas.SaveInfo, status: Components.Schemas.ServerStatus?) async {
        guard let client = client() else { return }
        busy = true
        folderProblem = nil
        defer { busy = false }
        startStamp = status?.lastImport?.finishedAt
        do {
            switch try await client.setSave(body: .json(.init(csvDir: save.csvDir, saveName: save.name))) {
            case .ok:
                break
            case .badRequest(let refused):
                folderProblem = try refused.body.json.error
                return
            case .undocumented(let code, _):
                folderProblem = "HTTP \(code)"
                return
            }
        } catch {
            folderProblem = String(describing: error)
            return
        }
        chosen = save
        progress = nil
        importProblem = nil
        sawImportRunning = false
        step = .importing
        await readStatus(client)
    }

    // MARK: The import

    /// Follows the import from a served status (the event stream keeps the app's status current; the window passes
    /// each one on). It has landed when the last import's finish time moves; it failed when the server reports an
    /// error after it ran.
    public func observe(_ status: Components.Schemas.ServerStatus?) async {
        guard step == .importing, importProblem == nil, let status else { return }
        if status.importing {
            sawImportRunning = true
            if let next = status.importProgress { progress = next }
            return
        }
        let stamp = status.lastImport?.finishedAt
        if let stamp, stamp != startStamp {
            await importLanded()
        } else if sawImportRunning, let error = status.lastError, !error.isEmpty {
            importProblem = .served(error)
        } else if sawImportRunning {
            await importLanded()
        } else if !status.csvDirExists {
            importProblem = .didNotStart
        }
    }

    /// Try Again after a failed import (`POST /api/import`).
    public func retryImport(status: Components.Schemas.ServerStatus?) async {
        guard let client = client() else { return }
        busy = true
        defer { busy = false }
        startStamp = status?.lastImport?.finishedAt
        sawImportRunning = false
        progress = nil
        do {
            switch try await client.startImport() {
            case .ok:
                importProblem = nil
            case .badRequest(let refused):
                importProblem = .served(try refused.body.json.error)
                return
            case .undocumented(let code, _):
                importProblem = .request("HTTP \(code)")
                return
            }
        } catch {
            importProblem = .request(String(describing: error))
            return
        }
        await readStatus(client)
    }

    private func readStatus(_ client: Client) async {
        if let status = try? await client.getStatus().ok.body.json {
            await observe(status)
        }
    }

    private func importLanded() async {
        progress = nil
        step = .pickClub
        await loadClubs()
    }

    // MARK: Pick the club

    /// Reads the clubs and preselects the served current club (else the one the save's human manages).
    public func loadClubs() async {
        guard let client = client() else { return }
        async let orgsAnswer = client.listOrgs()
        async let settingsAnswer = client.getSettings()
        let orgs = (try? await orgsAnswer.ok.body.json) ?? []
        let served = (try? await settingsAnswer.ok.body.json)?.organization?.id
        clubs = orgs.filter(\.isHuman) + orgs.filter { !$0.isHuman }
        selectedClub = clubs.first { $0.teamId == served }?.teamId ?? clubs.first?.teamId
    }

    /// Saves the chosen club as the configured one (`POST /api/settings`), then closes the window.
    public func saveClub() async {
        guard let club = selectedClub, let client = client() else { return }
        busy = true
        clubProblem = nil
        defer { busy = false }
        do {
            _ = try await client.saveSettings(body: .json(.init(defaultOrgId: club))).ok
        } catch {
            clubProblem = String(describing: error)
            return
        }
        await onClubSaved()
        step = .done
    }

    #if DEBUG
    /// A model at a given step, for `#Preview`s and snapshots.
    public static func preview(
        step: Step,
        saves: [Components.Schemas.SaveInfo] = [],
        locations: [Components.Schemas.SearchLocation] = [],
        folderProblem: String? = nil,
        chosen: Components.Schemas.SaveInfo? = nil,
        progress: Components.Schemas.ImportProgress? = nil,
        importProblem: ImportProblem? = nil,
        clubs: [Components.Schemas.Org] = []
    ) -> SetupModel {
        let model = SetupModel(client: { nil })
        model.step = step
        model.saves = saves
        model.savesLoaded = true
        model.locations = locations
        model.folderProblem = folderProblem
        model.chosen = chosen
        model.progress = progress
        model.importProblem = importProblem
        model.clubs = clubs.filter(\.isHuman) + clubs.filter { !$0.isHuman }
        model.selectedClub = model.clubs.first?.teamId
        return model
    }
    #endif
}
