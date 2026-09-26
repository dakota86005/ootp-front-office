import PennantAPI
import PennantKit
import SwiftUI

/// The main window at N3: the server's state. Everything shown beyond structural labels is served (the status's
/// app name and version, the data folder, the save, the club, the import's table and counts) or the server's own
/// sentence (why it could not start).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.serverState {
            case .idle, .starting:
                WaitingView(title: "Starting…")
            case .restarting:
                WaitingView(title: "Restarting…")
            case .stopping, .stopped:
                WaitingView(title: "Stopping…")
            case .ready:
                ReadyView()
            case .failed(let failure):
                ServerProblemView(
                    title: failure.kind.title,
                    symbol: "exclamationmark.triangle",
                    serverMessage: failure.serverMessage
                )
            case .locked(let message):
                ServerProblemView(title: "The data folder is in use", symbol: "lock", serverMessage: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ServerFailure.Kind {
    /// A structural title for each way the server can fail to run; the reason itself is the server's sentence.
    var title: LocalizedStringKey {
        switch self {
        case .notInstalled: "The server is missing from this build"
        case .couldNotLaunch, .handshake: "The server could not be started"
        case .notReady: "The server did not start in time"
        case .statusCheck: "The server did not answer"
        case .crashedRepeatedly: "The server keeps stopping"
        }
    }
}

private struct WaitingView: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("server.waiting")
    }
}

/// Failed or locked: what happened, the server's own words when it said any, the data folder, and the two ways on.
private struct ServerProblemView: View {
    @Environment(AppModel.self) private var model
    let title: LocalizedStringKey
    let symbol: String
    let serverMessage: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            VStack(spacing: 8) {
                if let serverMessage, !serverMessage.isEmpty {
                    Text(verbatim: serverMessage)
                }
                LabeledContent("Data folder") {
                    Text(verbatim: model.configuration.dataFolder.plainPath)
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
        } actions: {
            HStack {
                Button("Show Log") {
                    NSWorkspace.shared.open(model.logFile)
                }
                Button("Try Again") {
                    Task { await model.tryAgain() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .accessibilityIdentifier("server.problem")
    }
}

/// Ready: the status's name and version, the data folder, and the save, club and import the server reports.
private struct ReadyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if let status = model.status {
                Section {
                    LabeledContent("Version") { Text(verbatim: status.app.version) }
                    LabeledContent("Data folder") {
                        Text(verbatim: model.dataFolderPath).textSelection(.enabled)
                    }
                    if let save = status.saveName {
                        LabeledContent("Save") { Text(verbatim: save) }
                    }
                    if let label = model.club?.org?.label {
                        LabeledContent("Club") { Text(verbatim: label) }
                    }
                } header: {
                    Text(verbatim: status.app.name)
                        .font(.title2.bold())
                }
                if status.importing {
                    Section("Import") {
                        ImportProgressRow(progress: status.importProgress)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("server.ready")
    }
}

private struct ImportProgressRow: View {
    let progress: Components.Schemas.ImportProgress?

    var body: some View {
        if let progress, progress.files > 0 {
            ProgressView(value: Double(progress.fileIndex), total: Double(progress.files)) {
                Text(verbatim: progress.table)
            } currentValueLabel: {
                if let share = ServedFormat.share(progress.fileIndex, of: progress.files) {
                    Text(verbatim: share)
                }
            }
        } else {
            ProgressView()
        }
    }
}

#if DEBUG
#Preview("Ready, from the captured status") {
    RootView()
        .environment(PreviewModels.ready())
        .frame(width: 720, height: 480)
}
#endif
