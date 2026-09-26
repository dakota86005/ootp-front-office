import FeatureCore
import PennantAPI
import PennantKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings (SWIFTUI_REBUILD.md section 3.1): General (the save and data folder, importing, the data status, naming
/// the save folder by hand, restoring the first-run backup), Appearance, and AI (each provider's key status, read
/// only until N13). Updates arrive with N14. Every value shown is served; the labels are structural.
public struct SettingsView: View {
    @Environment(AppRouting.self) private var routing
    @Environment(AppModel.self) private var model

    public static let size = CGSize(width: 620, height: 640)

    public init() {}

    public var body: some View {
        @Bindable var routing = routing
        TabView(selection: $routing.settingsTab) {
            Tab("General", systemImage: "gearshape", value: AppRouting.SettingsTab.general) {
                GeneralSettings()
            }
            Tab("Appearance", systemImage: "circle.lefthalf.filled", value: AppRouting.SettingsTab.appearance) {
                AppearanceSettings()
            }
            Tab("AI", systemImage: "sparkles", value: AppRouting.SettingsTab.ai) {
                AISettings()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: AppAppearance.served(model.settings), initial: true) { _, theme in
            AppAppearance.apply(theme)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouting.self) private var routing
    @Environment(\.openWindow) private var openWindow
    @State private var importProblem: String?
    @State private var confirmingRestore = false
    @State private var restoreOutcome: RestoreOutcome?
    @State private var saveFolder = ""
    @State private var saveFolderProblem: String?
    @State private var choosingSaveFolder = false

    enum RestoreOutcome: Equatable {
        case restored(String)
        case failed(String)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                saveSection
                clubSection
                dataFolderSection
                saveFolderSection
                DataStatusSection(dataStatus: model.dataStatus)
                    .id("dataStatus")
            }
            .formStyle(.grouped)
            .onChange(of: routing.revealDataStatus, initial: true) { _, reveal in
                guard reveal else { return }
                withAnimation { proxy.scrollTo("dataStatus", anchor: .top) }
                routing.revealDataStatus = false
            }
        }
        .accessibilityIdentifier("settings.general")
    }

    private var saveSection: some View {
        Section("Save") {
            LabeledContent("Save") {
                if let name = model.status?.saveName { Text(verbatim: name) } else { Text("None chosen") }
            }
            if let folder = model.status?.csvDir {
                LabeledContent("Export folder") {
                    Text(verbatim: folder).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                }
            }
            if model.isImporting {
                ImportProgressView(progress: model.importProgress)
            }
            if let problem = importProblem ?? model.lastImportError {
                Label { Text(verbatim: problem) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Choose Save…") {
                    routing.requestSetup()
                    openWindow(id: SceneID.setup)
                }
                .disabled(!model.isReady)
                Spacer()
                Button("Import Now") {
                    Task { importProblem = await model.startImport() }
                }
                .disabled(!CommandAvailability.of(model, window: nil).refreshData)
                .accessibilityIdentifier("settings.importNow")
            }
        }
    }

    @ViewBuilder
    private var clubSection: some View {
        if !model.orgs.isEmpty {
            Section("Club") {
                Picker("Club", selection: Binding(
                    get: { model.club?.ref.id },
                    set: { id in
                        guard let id else { return }
                        Task { try? await model.saveSettings(.init(defaultOrgId: id)) }
                    }
                )) {
                    ForEach(model.orgs, id: \.teamId) { org in
                        Text(verbatim: org.label).tag(Optional(org.teamId))
                    }
                }
                .accessibilityIdentifier("settings.club")
            }
        }
    }

    private var dataFolderSection: some View {
        Section("Data folder") {
            LabeledContent("Data folder") {
                Text(verbatim: model.dataFolderPath).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.dataFolderPath)])
                }
                Spacer()
                Button("Restore Backup…") { confirmingRestore = true }
                    .disabled(model.backups.record() == nil)
                    .accessibilityIdentifier("settings.restoreBackup")
            }
            if let record = model.backups.record() {
                LabeledContent("Backup taken") {
                    Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                }
            } else {
                LabeledContent("Backup taken") { Text("None yet") }
            }
            if let restoreOutcome {
                switch restoreOutcome {
                case .restored(let folder):
                    LabeledContent("Replaced files kept in") { Text(verbatim: folder).textSelection(.enabled) }
                case .failed(let reason):
                    Label { Text(verbatim: reason) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Restore the backup?", isPresented: $confirmingRestore) {
            Button("Restore Backup", role: .destructive) {
                Task {
                    do {
                        let aside = try await model.restoreBackup()
                        restoreOutcome = .restored(aside.path(percentEncoded: false))
                    } catch {
                        restoreOutcome = .failed(String(describing: error))
                    }
                }
            }
        } message: {
            Text("Pennant stops its server, puts back the files it copied before it first ran on this folder, and starts again. The files it replaces are kept in the backups folder.")
        }
    }

    private var saveFolderSection: some View {
        Section {
            HStack {
                TextField("Save folder", text: $saveFolder, prompt: Text(verbatim: "…/Your Save.lg"))
                    .accessibilityIdentifier("settings.saveFolder")
                Button("Choose…") { choosingSaveFolder = true }
            }
            HStack {
                Button("Find Automatically") { Task { await setSaveFolder("") } }
                Spacer()
                Button("Use This Folder") { Task { await setSaveFolder(saveFolder) } }
                    .disabled(saveFolder.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let saveFolderProblem {
                Label { Text(verbatim: saveFolderProblem) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Save folder")
        }
        .fileImporter(isPresented: $choosingSaveFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { saveFolder = url.path(percentEncoded: false) }
        }
    }

    /// `POST /api/save-source`: the save's `.lg` folder named by hand; empty returns to finding it automatically.
    private func setSaveFolder(_ path: String) async {
        guard let client = model.client else { return }
        saveFolderProblem = nil
        do {
            switch try await client.setSaveSource(body: .json(.init(lgPath: path.trimmingCharacters(in: .whitespaces)))) {
            case .ok:
                await model.reloadAll()
            case .badRequest(let refused):
                saveFolderProblem = try refused.body.json.error
            case .undocumented(let code, _):
                saveFolderProblem = "HTTP \(code)"
            }
        } catch {
            saveFolderProblem = String(describing: error)
        }
    }
}

/// The data status as served (`/api/data-status`): the server's own headline, reasons and suggested action, and the
/// dates and places it reports. Only served values; a value the server did not send is left out, and the status
/// codes are not put into words here (the server will serve them, N4).
struct DataStatusSection: View {
    let dataStatus: Components.Schemas.DataStatus?

    var body: some View {
        Section("Data status") {
            if let status = dataStatus {
                Text(verbatim: status.freshness.headline)
                    .font(.headline)
                if !status.freshness.reasons.isEmpty {
                    lines(status.freshness.reasons)
                }
                if let action = status.freshness.action {
                    Label { Text(verbatim: action) } icon: { Image(systemName: "arrow.forward.circle") }
                }
                row("Game date", status.csv.currentDate)
                row("Imported data through", status.csv.simulatedThrough)
                row("Save through", status.save.simulatedThrough)
                row("Exported", ServedText.timestamp(status.csv.exportedAt))
                row("Imported", ServedText.timestamp(status.csv.importedAt))
                row("Save", status.save.name)
                row("Save folder", status.save.lgPath)
                if !status.save.discoveryNotes.isEmpty {
                    lines(status.save.discoveryNotes).font(.callout)
                }
                if let error = status.transactionLog.error?.message {
                    LabeledContent("Transaction log") { Text(verbatim: error) }
                }
            } else {
                ProgressView()
            }
        }
        .accessibilityIdentifier("settings.dataStatus")
    }

    /// Served sentences, one row (a list's rows need identities of their own, and sentences can repeat).
    private func lines(_ texts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text)
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) { Text(verbatim: value).textSelection(.enabled) }
        }
    }
}

// MARK: Appearance

struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(
                    get: { AppAppearance.served(model.settings) ?? "system" },
                    set: { theme in
                        AppAppearance.apply(theme)
                        Task {
                            do {
                                try await model.saveSettings(.init(theme: .init(value1: .init(rawValue: theme))))
                                problem = nil
                            } catch {
                                problem = String(describing: error)
                            }
                        }
                    }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .disabled(model.settings == nil)
                .accessibilityIdentifier("settings.appearance")
                if let problem {
                    Text(verbatim: problem).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: AI

/// Each AI provider and its key's status, as served (`/api/settings/providers`). Read only: adding or changing a key
/// arrives with the staff room (N13).
struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var providers: Components.Schemas.ProvidersResponse?
    private let preloaded: Components.Schemas.ProvidersResponse?

    init(preloaded: Components.Schemas.ProvidersResponse? = nil) {
        self.preloaded = preloaded
    }

    var body: some View {
        Form {
            if let answer = providers ?? preloaded {
                Section("Providers") {
                    ForEach(answer.providers, id: \.label) { provider in
                        ProviderRow(
                            provider: provider,
                            key: answer.keys.status(for: provider.id),
                            inUse: model.settings?.settings.provider == provider.id
                        )
                    }
                }
                Section {
                    Text("Adding or changing a key arrives in a later build")
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task(id: model.storeKey) {
            guard preloaded == nil, let client = model.client else { return }
            providers = try? await client.getProviders().ok.body.json
        }
        .accessibilityIdentifier("settings.ai")
    }
}

private struct ProviderRow: View {
    let provider: Components.Schemas.ProviderChoice
    let key: Components.Schemas.KeyStatus?
    let inUse: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                keyLine
                Text(verbatim: provider.model).font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: provider.label)
                if inUse {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var keyLine: some View {
        if !provider.requiresKey {
            Text("No key needed")
        } else if let key, key.configured {
            HStack(spacing: 4) {
                if let hint = key.hint { Text(verbatim: hint).monospaced() }
                switch key.source?.value1 {
                case .keychain: Text("From the Keychain").foregroundStyle(.secondary)
                case .env: Text("From the environment").foregroundStyle(.secondary)
                case .stored: Text("Saved in the data folder").foregroundStyle(.secondary)
                case nil: EmptyView()
                }
            }
        } else {
            Text("No key")
        }
    }
}

extension Components.Schemas.ProvidersResponse.KeysPayload {
    /// The key status for a provider id, or nil for a provider this build's contract does not list.
    func status(for id: Components.Schemas.ProviderId) -> Components.Schemas.KeyStatus? {
        switch id.value1 {
        case .anthropic: anthropic
        case .openai: openai
        case .gemini: gemini
        case .opencode: opencode
        case .ollama: ollama
        case nil: nil
        }
    }
}
